#!/bin/bash
PASSWORD=Password12#
TIMEZONE="America/Edmonton"
SWAPSIZE=512
HOSTNAME="gentoo-machine"
DOMAIN="cluster1.victorprocure.co"
SOURCE=http://gentoo.mirrors.tera-byte.com/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64-20180116T214503Z.tar.xz

#Setup Drive /dev/sda
parted -a optimal --script /dev/sda -- \
    mklabel gpt \
    unit MiB \
    mkpart primary 1 3 \
    name 1 grub \
    set 1 bios_grub on \
    mkpart primary 3 131 \
    name 2 boot \
    set 2 boot on \
    mkpart primary 131 $(expr 131 + $[SWAPSIZE]) \
    name 3 swap \
    mkpart primary 643 -1 \
    name 4 rootfs

#Create filesystems
mkswap /dev/sda3
swapon /dev/sda3

mkfs.ext2 /dev/sda2
mkfs.ext4 /dev/sda4

#Mount root
mount /dev/sda4 /mnt/gentoo

#Set Time
ntpd -q -g

#Download tarball Stage3
cd /mnt/gentoo
wget $SOURCE
wget $SOURCE.DIGESTS
wget $SOURCE.asc

#Verify Download
openssl dgst -r -sha512 stage3*.tar.xz

#Unpack
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

#Configure Make file
echo MAKEOPTS=\"-j2\" >> /mnt/gentoo/etc/portage/make.conf
echo CXXFLAGS=\"\${CFLAGS}\" >> /mnt/gentoo/etc/portage/make.conf
sed -i 's/CFLAGS=.*/CFLAGS=\"-march=native -O2 -pipe\"/' /mnt/gentoo/etc/portage/make.conf


#Select closest mirrors
mirrorselect -o -D -R 'North America' -q -s 5 >> /mnt/gentoo/etc/portage/make.conf

#Copy DNS
cp --dereference /etc/resolve.conf /mnt/gentoo/etc

#Mount necessary filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/dev

#Enter new environment
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) ${PS1}"

#Mount Boot
mkdir /boot
mount /dev/sda2 /boot

#Update Portage
emerge-webrsync

#Update Ebuild Repo
emerge --sync

#Select latest systemd profile
eselect profile set $(eselect profile list | grep 'systemd (stable)' | tail -1 | grep -Eio '\[[0-9]+\]' | grep -Eo '[0-9]+')

#Update the @world set
emerge -yDNu @world
emerge --depclean

#Set timezone
echo $TIMEZONE > /etc/timezone
emerge --config sys-libs/timezone-data

#Configure Locales
sed -i -e 's/#\(en_US\)/\1/' /etc/locale.gen
locale-gen

#Select Locale
eselect locale set $(eselect locale list | grep -Ei 'en_US.utf8' | grep -Eio '\[[0-9]+\]' | grep -Eio '[0-9]+')
env-update && source /etc/profile && export PS1="(CHROOT) $PS1"

#Install Genkernel
emerge gentoo-sources
emerge sys-kernel/genkernel-next
emerge --deselect sys-fs/udev

#Configure fstab
BOOT=$(blkid | grep -e '/dev/sda2' | grep -Eio '\sUUID=\"[0-9a-zA-Z\-]+\"' | sed 's/\"//g; s/\s//g')
ROOT=$(blkid | grep -e '/dev/sda2' | grep -Eio '\sUUID=\"[0-9a-zA-Z\-]+\"' | sed 's/\"//g; s/\s//g')
SWAP=$(blkid | grep -e '/dev/sda2' | grep -Eio '\sUUID=\"[0-9a-zA-Z\-]+\"' | sed 's/\"//g; s/\s//g')

cat << EOF >> /etc/fstab
$BOOT    /boot    ext2    defaults,noatime    0 2
$SWAP    none     swap    sw                  0 0
$ROOT    /        ext4    noatime             0 1
EOF

#mtab
ln -sf /proc/self/mounts /etc/mtab

#Configure kernel
echo "UDEV=\"yes\"" >> /etc/genkernel.conf
cd /usr/src/linux
CONFIG_VAR=(CONFIG_BLK_DEV_SD CONFIG_EXT2_FS CONFIG_EXT2_FS_XATTR CONFIG_EXT2_FS_POSIX_ACL CONFIG_EXT2_FS_SECURITY CONFIG_EXT3_FS CONFIG_EXT3_FS_POSIX_ACL CONFIG_EXT3_FS_SECURITY CONFIG_PARTITION_ADVANCED CONFIG_EFI_PARTITION CONFIG_EFI CONFIG_EFI_STUB CONFIG_EFI_MIXED CONFIG_EFI_VARS CONFIG_GENTOO_LINUX_INIT_SYSTEMD CONFIG_EXPERT CONFIG_HYPERVISOR_GUEST CONFIG_PARAVIRT CONFIG_KVM_GUEST CONFIG_VIRTIO_PCI CONFIG_BLK_DEV CONFIG_VIRTIO_BLK CONFIG_VIRTIO_NET CONFIG_SCSI_LOWLEVEL CONFIG_SCSI_VIRTIO)
cp .config /root/kernel.config

for i in ${CONFIG_VAR[@]}; do
    grep "${i}=" /root/kernel.config
    if [ ! $? -eq 0 ]; then
        echo "${i}=y" >> /root/kernel.config
    else
        sed -ir "s/^(${i}=.*|# ${i} is not set)/${i}=y" /root/kernel.config
    fi
done

#Generate Kernel
genkernel --udev --install all

#Configure Network Names
echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname
cat << EOF > /etc/conf.d/net
dns_domain_lo="$DOMAIN"
config_eth0="dhcp"
EOF

#Auto start networking
emerge dhcpcd
cd /etc/init.d
ln -s net.lo net.eth0
systemctl enable dhcpcd

#Set password
passwd << EOF
$PASSWORD
$PASSWORD
EOF

#Configure Logger
emerge syslog-ng
systemctl enable syslog-ng

#Configure Bootloader
emerge sys-boot/grub:2
echo "GRUB_CMDLINE_LINUX=\"init=/lib/systemd/systemd\"" >> /etc/default/grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg


#Remove stage tar
rm /stage3-*

#Reboot
exit
cd 
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot