#!/bin/bash
set -ex

TMPDOWN=$(realpath $1)
KERNEL_OBJ=$(realpath $2)
RAMDISK=$(realpath $3)
OUT=$(realpath $4)
INSTALL_MOD_PATH="$(realpath $5)"

HERE=$(pwd)
source "${HERE}/deviceinfo"

case "$deviceinfo_arch" in
    aarch64*) ARCH="arm64" ;;
    arm*) ARCH="arm" ;;
    x86_64) ARCH="x86_64" ;;
    x86) ARCH="x86" ;;
esac

case "${deviceinfo_ramdisk_compression:=gzip}" in
    gzip)
        COMPRESSION_CMD="gzip -9"
        ;;
    lz4)
        COMPRESSION_CMD="lz4 -l -9"
        ;;
    *)
        echo "Unsupported deviceinfo_ramdisk_compression value: '$deviceinfo_ramdisk_compression'"
        exit 1
        ;;
esac

if [ "$deviceinfo_ramdisk_compression" != "gzip" ]; then
    gzip -dc "$RAMDISK" | $COMPRESSION_CMD > "${RAMDISK}.${deviceinfo_ramdisk_compression}"
    RAMDISK="${RAMDISK}.${deviceinfo_ramdisk_compression}"
fi

if [ -d "$HERE/ramdisk-overlay" ]; then
    cp "$RAMDISK" "${RAMDISK}-merged"
    RAMDISK="${RAMDISK}-merged"
    cd "$HERE/ramdisk-overlay"
    find . | cpio -o -H newc | $COMPRESSION_CMD >> "$RAMDISK"

    # Restore unoverlayed recovery ramdisk
    if [ -f "$HERE/ramdisk-overlay/ramdisk-recovery.img" ] && [ -f "$TMPDOWN/ramdisk-recovery.img-original" ]; then
        mv "$TMPDOWN/ramdisk-recovery.img-original" "$HERE/ramdisk-overlay/ramdisk-recovery.img"
    fi
fi

if [ -n "$deviceinfo_kernel_image_name" ]; then
    KERNEL="$KERNEL_OBJ/arch/$ARCH/boot/$deviceinfo_kernel_image_name"
else
    # Autodetect kernel image name for boot.img
    if [ "$deviceinfo_bootimg_header_version" -ge 2 ]; then
        IMAGE_LIST="Image.gz Image"
    else
        IMAGE_LIST="Image.gz-dtb Image.gz Image"
    fi

    for image in $IMAGE_LIST; do
        if [ -e "$KERNEL_OBJ/arch/$ARCH/boot/$image" ]; then
            KERNEL="$KERNEL_OBJ/arch/$ARCH/boot/$image"
            break
        fi
    done
fi

if [ -n "$deviceinfo_bootimg_prebuilt_dtb" ]; then
    DTB="$HERE/$deviceinfo_bootimg_prebuilt_dtb"
elif [ -n "$deviceinfo_dtb" ]; then
    DTB="$KERNEL_OBJ/../$deviceinfo_codename.dtb"
    PREFIX=$KERNEL_OBJ/arch/$ARCH/boot/dts/
    DTBS="$PREFIX${deviceinfo_dtb// / $PREFIX}"
    if [ -n "$deviceinfo_dtb_has_dt_table" ] && $deviceinfo_dtb_has_dt_table; then
        echo "Appending DTB partition header to DTB"
        python2 "$TMPDOWN/libufdt/utils/src/mkdtboimg.py" create "$DTB" $DTBS --id="${deviceinfo_dtb_id:-0x00000000}" --rev="${deviceinfo_dtb_rev:-0x00000000}" --custom0="${deviceinfo_dtb_custom0:-0x00000000}" --custom1="${deviceinfo_dtb_custom1:-0x00000000}" --custom2="${deviceinfo_dtb_custom2:-0x00000000}" --custom3="${deviceinfo_dtb_custom3:-0x00000000}"
    else
        cat $DTBS > $DTB
    fi
fi

if [ -n "$deviceinfo_bootimg_prebuilt_dt" ]; then
    DT="$HERE/$deviceinfo_bootimg_prebuilt_dt"
elif [ -n "$deviceinfo_bootimg_dt" ]; then
    PREFIX=$KERNEL_OBJ/arch/$ARCH/boot
    DT="$PREFIX/$deviceinfo_bootimg_dt"
fi

if [ -n "$deviceinfo_prebuilt_dtbo" ]; then
    DTBO="$HERE/$deviceinfo_prebuilt_dtbo"
elif [ -n "$deviceinfo_dtbo" ]; then
    DTBO="$(dirname "$OUT")/dtbo.img"
fi

MKBOOTIMG="$TMPDOWN/android_system_tools_mkbootimg/mkbootimg.py"
EXTRA_ARGS=""

EXTRA_ARGS+=" --base $deviceinfo_flash_offset_base --kernel_offset $deviceinfo_flash_offset_kernel --ramdisk_offset $deviceinfo_flash_offset_ramdisk --second_offset $deviceinfo_flash_offset_second --tags_offset $deviceinfo_flash_offset_tags --pagesize $deviceinfo_flash_pagesize"

if [ "$deviceinfo_bootimg_header_version" -eq 0 ] && [ -n "$DT" ]; then
    EXTRA_ARGS+=" --dt $DT"
fi

if [ "$deviceinfo_bootimg_header_version" -eq 2 ]; then
    EXTRA_ARGS+=" --dtb $DTB --dtb_offset $deviceinfo_flash_offset_dtb"
fi

if [ -n "$deviceinfo_bootimg_board" ]; then
    EXTRA_ARGS+=" --board $deviceinfo_bootimg_board"
fi

"$MKBOOTIMG" --kernel "$KERNEL" --ramdisk "$RAMDISK" --cmdline "$deviceinfo_kernel_cmdline" --header_version $deviceinfo_bootimg_header_version -o "$OUT" --os_version $deviceinfo_bootimg_os_version --os_patch_level $deviceinfo_bootimg_os_patch_level $EXTRA_ARGS
