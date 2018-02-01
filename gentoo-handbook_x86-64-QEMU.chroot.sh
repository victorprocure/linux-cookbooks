#!/bin/bash
PASSWORD=Password12#
TIMEZONE="America/Edmonton"
HOSTNAME="gentoo-machine"
DOMAIN="cluster1.victorprocure.co"

#Enter new environment
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
emerge gentoo-sources
emerge -DN @world
emerge --depclean

#Set timezone
echo $TIMEZONE > /etc/timezone
emerge --config sys-libs/timezone-data

#Configure Locales
sed -i -e 's/#\(en_US\)/\1/' /etc/locale.gen
locale-gen

#Select Locale
eselect locale set $(eselect locale list | grep -i 'en_US.utf8' | grep -Eio '\[[0-9]+\]' | grep -Eo '[0-9]+')
env-update && source /etc/profile && export PS1="(CHROOT) $PS1"

#Install Genkernel
emerge sys-kernel/genkernel-next
#emerge --deselect sys-fs/udev

#Configure fstab
BOOT=$(blkid | grep -e '/dev/sda2' | grep -Eio '\sUUID=\"[0-9a-zA-Z\-]+\"' | sed 's/\"//g; s/\s//g')
ROOT=$(blkid | grep -e '/dev/sda4' | grep -Eio '\sUUID=\"[0-9a-zA-Z\-]+\"' | sed 's/\"//g; s/\s//g')
SWAP=$(blkid | grep -e '/dev/sda3' | grep -Eio '\sUUID=\"[0-9a-zA-Z\-]+\"' | sed 's/\"//g; s/\s//g')

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

make defconfig
cp .config /root/kernel.config

for i in ${CONFIG_VAR[@]}; do
    grep "${i}=" /root/kernel.config
    if [ ! $? -eq 0 ]; then
        echo "${i}=y" >> /root/kernel.config
    else
        sed -ir "s/^(${i}=.*|# ${i} is not set)/${i}=y/" /root/kernel.config
    fi
done

#Generate Kernel
genkernel --udev --install --kernel-config=/root/kernel.config all

#Configure Network Names
echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname
cat << EOF > /etc/conf.d/net
dns_domain_lo="$DOMAIN"
config_eth0="dhcp"
EOF

#Auto start networking
#emerge dhcpcd
#cd /etc/init.d
#ln -s net.lo net.eth0
#systemctl enable dhcpcd

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