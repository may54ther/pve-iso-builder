#!/bin/bash
script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
extra_pkg="ceph-common ceph-fuse"
hostarch=$(arch)
codename="bookworm"
targetdir="/tmp/pve-$RELEASE"
modules="hfs hfsplus cdrom sd_mod sr_mod loop squashfs iso9660 drm overlay uas hibmc-drm dw_drm_dsi kirin_drm amdgpu nouveau ast radeon virtio-gpu mgag200"

errlog() {
    if [ $? != 0 ]; then
        echo "$1"
        umount_proc
        exit 1
    fi
}

mount_proc() {
    mount -t proc /proc "$targetdir/rootfs/proc"
    mount -t sysfs /sys "$targetdir/rootfs/sys"
    mount -o bind /dev "$targetdir/rootfs/dev"
    mount -o bind /dev/pts "$targetdir/dev/pts"
}

umount_proc() {
    umount "$targetdir/rootfs/proc"
    umount "$targetdir/rootfs/sys"
    umount "$targetdir/rootfs/dev"
    umount "$targetdir/dev/rootfs/pts"
    umount -l "$targetdir/overlay/mount"
    umount -l "$targetdir/overlay/base"
}

generate_uuid() {
    local N B T
    for ((N = 0; N < 8; N++)); do
        B=$((RANDOM % 16))
        printf '%x' $B
    done
    printf '-'
    for ((N = 0; N < 3; N++)); do
        for ((i = 0; i < 4; i++)); do
            B=$((RANDOM % 16))
            printf '%x' $B
        done
        printf '-'
    done
    printf '4'
    for ((N = 0; N < 3; N++)); do
        B=$((RANDOM % 16))
        printf '%x' $B
    done
    T=$((RANDOM % 4 + 8))
    printf '%x' $T
    for ((N = 0; N < 3; N++)); do
        B=$((RANDOM % 16))
        printf '%x' $B
    done
}