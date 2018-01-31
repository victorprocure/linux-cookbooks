#!/bin/bash
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
wget $SOURCE.DIGESTS.asc

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
cp --dereference /etc/resolv.conf /mnt/gentoo/etc

#Mount necessary filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/dev

#Chroot into new environment
mkdir /mnt/gentoo/dev-scripts
cd /mnt/gentoo/dev-scripts
wget https://raw.githubusercontent.com/victorprocure/linux-cookbooks/master/gentoo-handbook_x86-64-QEMU.chroot.sh
chmod +x gentoo-handbook*.chroot.sh

chroot /mnt/gentoo /dev-scripts/gentoo-handbook_x86-64-QEMU.chroot.sh

cd 
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot