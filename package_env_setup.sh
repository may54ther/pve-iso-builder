#!/bin/bash
source "$(dirname "$0")/package_common.sh"

# Check env
env_test(){
    if [ "$EUID" -ne 0 ]; then
        errlog "This script must be run as root."
    fi
    test -f "/usr/sbin/debootstrap" || errlog "debootstrap not found, use 'apt install debootstrap' to install"
    test -f "/usr/bin/mksquashfs" || errlog "squasfs-tools not found, use 'apt install squashfs-tools' to install"
    test -f "/usr/bin/xorriso" || errlog "xorriso not found, use 'apt install xorriso' to install"
}

# Create isofs
isofs(){
    if [ ! -f "$targetdir/.isofs.lock" ];then
    rm $targetdir/iso/ -rf
    mkdir $targetdir/iso/boot/ -p
    mkdir $targetdir/iso/{.installer,.base,.installer-mp,.workdir} -p
    cp $script_dir/.cd-info $script_dir/Release.txt $script_dir/COPYING $script_dir/COPYRIGHT $script_dir/EULA   $targetdir/iso/  ||errlog "do copy elua to iso dir failed"
    cp -r $script_dir/proxmox $targetdir/iso/  ||errlog "do proxmox dir to iso dir failed"
    echo "" >  $targetdir/iso/auto-installer-capable
    touch  $targetdir/.isofs.lock
    fi
}

# Crate Proxmox VE iso info
isoinfo(){
echo $pveuuid > $targetdir/iso/.pve-cd-id.txt
}

# Build pve-base.squashfs
buildroot(){
    if [ ! -f "$targetdir/pve-base.squashfs" ];then
	if [  "$hostarch" == "loongarch64" ];then
		debootstrap --arch=$target_arch  --include=debian-ports-archive-keyring --exclude="exim4,exim4-base,usr-is-merged" --include="usrmerge,perl" --no-check-gpg $codename $targetdir/rootfs $portmirrors/debian-ports/debian || errlog "debootstrap failed"
		chroot $targetdir/rootfs apt install usr-is-merged -y
		echo 'APT { Get { AllowUnauthenticated "1"; }; };' > $targetdir/rootfs/etc/apt/apt.conf.d/99allow_unauth
		chroot $targetdir/rootfs apt clean
	else
		debootstrap --arch=$target_arch $codename $targetdir/rootfs $mirrors/debian || errlog "debootstrap failed"
		echo "deb $mirrors/debian/ $codename main contrib non-free non-free-firmware" > $targetdir/rootfs/etc/apt/sources.list
		echo "deb $mirrors/debian/ "$codename"-updates main contrib non-free non-free-firmware" >> $targetdir/rootfs/etc/apt/sources.list
		echo "deb $mirrors/debian/ "$codename"-backports main contrib non-free non-free-firmware" >> $targetdir/rootfs/etc/apt/sources.list
		echo "deb $mirrors/debian-security "$codename"-security main contrib non-free non-free-firmware" >> $targetdir/rootfs/etc/apt/sources.list
	fi
    mksquashfs $targetdir/rootfs $targetdir/pve-base.squashfs
    fi
}

# Download Proxmox VE Packages
create_pkg(){
    mount_proc
    if [ ! -f  "$targetdir/.package.lock" ];then
        if [ "$target_arch" == "amd64" ];then
            curl -L $pvemirrors/proxmox-release-$codename.gpg    -o $targetdir/rootfs/etc/apt/trusted.gpg.d/proxmox-release-$codename.gpg
            echo "deb $pvemirrors/$PRODUCT $codename $PRODUCT-no-subscription " > $targetdir/rootfs/etc/apt/sources.list.d/pveport.list  ||errlog "create apt mirrors failed"
        else
            curl -L $portmirrors/proxmox/debian/pveport.gpg -o $targetdir/rootfs/etc/apt/trusted.gpg.d/pveport.gpg ||errlog "download apt key failed"
            echo "deb $portmirrors/proxmox/debian/$PRODUCT $codename port pvetest" > $targetdir/rootfs/etc/apt/sources.list.d/pveport.list  ||errlog "create apt mirrors failed"
        fi 
    chroot $targetdir/rootfs apt clean
    rm -rf $targetdir/rootfs/var/cache/apt/archives/
    chroot $targetdir/rootfs apt update ||errlog "do apt update failed"

    if [ "$PRODUCT" == "pve" ];then
	main_pkg="proxmox-ve"
    else
	main_pkg="proxmox-backup-server"
    fi

    if [ -f "proxmox/$PRODUCT-packages.list.line" ];then
        main_pkg=`cat proxmox/$PRODUCT-packages.list.line`
    fi

    chroot $targetdir/rootfs apt --download-only install -y  $main_pkg postfix squashfs-tools traceroute net-tools pci.ids pciutils efibootmgr xfsprogs fonts-liberation dnsutils $extra_pkg $grub_pkg gettext-base sosreport ethtool dmeventd eject chrony locales locales-all systemd rsyslog ifupdown2 ksmtuned zfsutils-linux zfs-zed spl btrfs-progs gdisk bash-completion zfs-initramfs dosfstools||errlog "download proxmox-ve package failed"

    if [ ! -z "$extra_kernel" ] && [ "$PRODUCT" != "pbs" ] ;then
	if [ "$target_arch" == "arm64"  ]  || [ "$target_arch" == "loong64"  ] ;then
        	chroot $targetdir/rootfs apt --download-only install -y  $extra_kernel ||errlog "kernel installed failed"
    	fi
    fi

    if [ "$target_arch" != "amd64" ];then
        chroot $targetdir/rootfs apt --download-only install -y $main_kernel  ||errlog "kernel installed failed"
    fi

    mkdir $targetdir/iso/proxmox/packages/ -p
    cp -r $targetdir/rootfs/var/cache/apt/archives/*.deb $targetdir/iso/proxmox/packages/  ||errlog "do copy pkg failed"
    touch $targetdir/.package.lock
    fi

    if [ ! -f "$targetdir/.mainkernel.lock" ];then
        chroot $targetdir/rootfs apt install initramfs-tools -y
	    initramfs_hook
	    chroot $targetdir/rootfs apt install pve-firmware $main_kernel -y ||errlog "kernel installed failed"
	    echo "copy main kernel"
	    cp $targetdir/rootfs/boot/initrd.img-* $targetdir/iso/boot/initrd.img  ||errlog "do copy initrd failed"
	    cp $targetdir/rootfs/boot/vmlinuz-*  $targetdir/iso/boot/linux26  ||errlog "do copy kernel failed"
	    touch $targetdir/.mainkernel.lock
    fi


    if [ ! -z "$extra_kernel"  ] && [ "$target_arch" != "amd64"  ] ;then

	chroot $targetdir/rootfs apt install $extra_kernel -y ||errlog "Extra kernel installed failed"

        if [[ "$extra_kernel" =~ "openeuler" ]];then
            cp $targetdir/rootfs/boot/initrd.img-*-openeuler $targetdir/iso/boot/initrd.img-openeuler  ||errlog "do copy initrd failed"
            cp $targetdir/rootfs/boot/vmlinuz-*-openeuler  $targetdir/iso/boot/linux26-openeuler  ||errlog "do copy kernel failed"
        fi

        if [[ "$extra_kernel" =~ -pve ]]; then
                cp $targetdir/rootfs/boot/initrd.img-*-pve $targetdir/iso/boot/initrd.img-pve  ||errlog "do copy initrd failed"
                cp $targetdir/rootfs/boot/vmlinuz-*-pve  $targetdir/iso/boot/linux26-pve  ||errlog "do copy kernel failed"
        fi

        if [[ "$extra_kernel" =~ -generic ]]; then
                cp $targetdir/rootfs/boot/initrd.img-*-generic $targetdir/iso/boot/initrd.img-generic  ||errlog "do copy initrd failed"
                cp $targetdir/rootfs/boot/vmlinuz-*-generic  $targetdir/iso/boot/linux26-generic  ||errlog "do copy kernel failed"
        fi

        if [[ "$extra_kernel" =~ phytium ]]; then
                cp $targetdir/rootfs/boot/initrd.img-*-phytium $targetdir/iso/boot/initrd.img-phytium  ||errlog "do copy initrd failed"
                cp $targetdir/rootfs/boot/vmlinuz-*-phytium  $targetdir/iso/boot/linux26-phytium  ||errlog "do copy kernel failed"
        fi
    fi

    if [ "$target_arch" == "amd64" ];then
	echo "copy x86_64 init"
        cp $targetdir/rootfs/boot/initrd.img* $targetdir/iso/boot/initrd.img  ||errlog "do copy initrd failed"
        cp $targetdir/rootfs/boot/vmlinuz*  $targetdir/iso/boot/linux26  ||errlog "do copy kernel failed"
    fi

    umount_proc
}

# Create pve-installer.squashfs
overlayfs(){
    if [ ! -f "$targetdir/.overlay.lock" ];then
        rm $targetdir/overlay/ -rf
        mkdir $targetdir/overlay/{base,upper,work,mount} -p
        mount -t squashfs -o ro $targetdir/pve-base.squashfs  $targetdir/overlay/base || errlog "mount pve-base.squashfs filesystem failed"
        mount -t overlay -o lowerdir=$targetdir/overlay/base,upperdir=$targetdir/overlay/upper,workdir=$targetdir/overlay/work  none $targetdir/overlay/mount || errlog "mount squashfs filesystem failed"

        if [ "$target_arch" == "amd64" ];then
            curl -L $pvemirrors/proxmox-release-$codename.gpg    -o $targetdir/overlay/mount/etc/apt/trusted.gpg.d/proxmox-release-$codename.gpg
            echo "deb $pvemirrors/$PRODUCT $codename $PRODUCT-no-subscription " > $targetdir/overlay/mount/etc/apt/sources.list.d/pveport.list  ||errlog "create apt mirrors failed"
        else
            curl -L $portmirrors/proxmox/debian/pveport.gpg -o $targetdir/overlay/mount/etc/apt/trusted.gpg.d/pveport.gpg ||errlog "download apt key failed"
            echo "deb $portmirrors/proxmox/debian/$PRODUCT $codename port" > $targetdir/overlay/mount/etc/apt/sources.list.d/pveport.list  ||errlog "create apt mirrors failed"
        fi
        chroot $targetdir/overlay/mount apt update || errlog "apt update failed"
        debconfig_set
        debconfig_write
        LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot $targetdir/overlay/mount apt -o DPkg::Options::="--force-confnew" install $grub_pkg openssh-client locales locales-all traceroute squashfs-tools spice-vdagent pci.ids pciutils gettext-base fonts-liberation eject ethtool efibootmgr dmeventd dnsutils lvm2 libstring-shellquote-perl console-setup wget curl vim iputils-* locales busybox initramfs-tools xorg openbox proxmox-installer pve-firmware zfsutils-linux zfs-zed spl btrfs-progs gdisk bash-completion zfs-initramfs dosfstools -y || errlog "install pveinstaller failed"
        fix_console_setup
        mkdir $targetdir/overlay/mount/usr/lib/modules/
        cp -r $targetdir/rootfs/lib/modules/* $targetdir/overlay/mount/usr/lib/modules/
        chroot $targetdir/overlay/mount/ apt clean
        rm -rf $targetdir/overlay/mount/var/cache/apt/archives/
        umount $targetdir/overlay/mount   || errlog "umount overlayfs failed"
        umount $targetdir/overlay/base  || errlog "umount pvebase overlayfs failed"
        touch $targetdir/.overlay.lock
    fi

    rm -rf $targetdir/overlay/upper/tmp/  $targetdir/pve-installer.squashfs
    cp $targetdir/iso/.pve-cd-id.txt $targetdir/overlay/upper/ || errlog "copy .pve-cd-id.txt  failed"
    cp $targetdir/iso/.cd-info $targetdir/overlay/upper/ || errlog "copy .cd-info  failed"
    mkdir  $targetdir/overlay/upper/cdrom -p
    mksquashfs $targetdir/overlay/upper/ $targetdir/pve-installer.squashfs || errlog "create pve-installer.squashfs failed"
    touch $targetdir/.pve-installer.lock
}

copy_squ(){
    cp $targetdir/pve-installer.squashfs $targetdir/iso/pve-installer.squashfs
    cp $targetdir/pve-base.squashfs $targetdir/iso/pve-base.squashfs
}

umount_proc
if [ "$1" == "clean" ]; then
    rm -rf "$targetdir"
    mkdir -p "$targetdir/rootfs"
fi
pveuuid=$(generate_uuid)
isodate=$(date +"%Y-%m-%d-%H-%M-%S-00")
env_test
isofs
isoinfo
buildroot
create_pkg
overlayfs
copy_squ