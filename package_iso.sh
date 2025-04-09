#!/bin/bash
source "$(dirname "$0")/package_common.sh"

# Install ISO Grub
grub_install(){
if [ ! -f "$targetdir/.grub.lock" ];then
    rm $targetdir/iso/boot/grub/ -rf
    rm $targetdir/iso/EFI -rf
    mkdir $targetdir/iso/EFI/BOOT/ -p
    mkdir $targetdir/iso/boot/grub -p
    echo "do grub install"
    grub-mkimage -o $targetdir/iso/EFI/BOOT/$grub_file -O $grub_prefix-efi -p /EFI/BOOT/ \
	boot linux chain normal configfile \
	part_gpt part_msdos fat iso9660 udf \
	test true keystatus loopback regexp probe \
	efi_gop all_video gfxterm font \
	echo read help ls cat halt reboot lvm ext2 xfs  hfsplus hfs \
    acpi search_label search search_fs_file search_fs_uuid \
    serial terminfo terminal zfs btrfs efifwsetup

    cp -r /boot/grub/ $targetdir/iso/boot/  ||errlog "do grub dir failed"
    cp $script_dir/grub.cfg $targetdir/iso/boot/grub/  ||errlog "do copy grub cfg  failed"
    cp -r $script_dir/pvetheme  $targetdir/iso/boot/grub/  ||errlog "do copy grub pvethem failed"
    touch $targetdir/.grub.lock
fi
cat > $targetdir/iso/EFI/BOOT/grub.cfg << EOF
search --fs-uuid --set=root $isodate
set prefix=(\${root})/boot/grub
source \${prefix}/grub.cfg
insmod part_acorn
insmod part_amiga
insmod part_apple
insmod part_bsd
insmod part_dfly
insmod part_dvh
insmod part_gpt
insmod part_msdos
insmod part_plan
insmod part_sun
insmod part_sunpc
EOF


}

# Include additional .deb files from pvepackage directory
include_custom_debs() {
    local deb_dir="$script_dir/pvepackage"
    if [ -d "$deb_dir" ]; then
        echo "Including custom .deb files from $deb_dir"
        for deb_file in "$deb_dir"/*.deb; do
            if [ -f "$deb_file" ]; then
                echo "Installing $deb_file into ISO environment"
                cp "$deb_file" "$targetdir/rootfs/var/cache/apt/archives/" || errlog "Failed to copy $deb_file"
                chroot $targetdir/rootfs dpkg -i "/var/cache/apt/archives/$(basename "$deb_file")" || errlog "Failed to install $deb_file"
            fi
        done
    else
        echo "No custom .deb files found in $deb_dir"
    fi
}

# Create efi.img
mkefi_img(){
    dd if=/dev/zero of=$targetdir/iso/boot/grub/efi.img bs=512 count=20480
    mkfs.fat -F 16 -n 'EFI' $targetdir/iso/boot/grub/efi.img
    rm /tmp/efi -rf
    mkdir /tmp/efi/
    mount $targetdir/iso/boot/grub/efi.img /tmp/efi
    cp -r $targetdir/iso/EFI  /tmp/efi  ||errlog "do EFI file failed"
    umount -l /tmp/efi
}


# Build iso for !amd64
build_iso(){
    rm $targetdir/iso/*.iso -rf
    isodate2=`echo $isodate|sed  "s/-//g"`
    cd $targetdir/iso/
    xorriso -as mkisofs -r  -V 'PVE' \
    --modification-date=$isodate2 \
    -o $targetdir/$ISONAME-$RELEASE-$ISORELEASE-$target_arch-$isodate2.iso \
    -R -cache-inodes \
    -iso-level 3 \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -append_partition 2 0xef boot/grub/efi.img \
    -partition_cyl_align all \
    -isohybrid-gpt-basdat -isohybrid-apm-hfsplus \
    .
    cd $script_dir
}

# Build iso for amd64
build_amd64_iso(){
    rm $targetdir/iso/*.iso -rf
    isodate2=`echo $isodate|sed  "s/-//g"`
    cd $targetdir/iso/
    cp $script_dir/boot.cat $targetdir/iso/boot  ||errlog "do copy boot.cat failed"
    cp $script_dir/iso.mbr $targetdir/iso/boot  ||errlog "do copy iso.mbr failed"
    cp $script_dir/eltorito.img $targetdir/iso/boot  ||errlog "do copy eltorito failed"
    xorriso -as mkisofs  \
    -V 'PVE' \
    -o $targetdir/$ISONAME-$RELEASE-$ISORELEASE-$target_arch-$isodate2.iso \
    --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt,zero_apm:'./boot/iso.mbr' \
    --modification-date=$isodate2 \
    -partition_cyl_align off \
    -partition_offset 0 \
    -partition_hd_cyl 67 \
    -partition_sec_hd 32 \
    -apm-block-size 2048 \
    -hfsplus \
    -efi-boot-part --efi-boot-image \
    -c '/boot/boot.cat' \
    -b '/boot/eltorito.img' \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    -eltorito-alt-boot \
    -e '/boot/grub/efi.img' \
    -no-emul-boot \
    -boot-load-size 16384 \
    .
}

grub_install
mkefi_img
include_custom_debs
if [ "$target_arch" == "amd64" ]; then
    build_amd64_iso
else
    build_iso
fi