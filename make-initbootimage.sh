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
    IMAGE_LIST="Image.gz Image"

    for image in $IMAGE_LIST; do
        if [ -e "$KERNEL_OBJ/arch/$ARCH/boot/$image" ]; then
            KERNEL="$KERNEL_OBJ/arch/$ARCH/boot/$image"
            break
        fi
    done
fi

MKBOOTIMG="$TMPDOWN/android_system_tools_mkbootimg/mkbootimg.py"
EXTRA_ARGS=""

if [ -n "$deviceinfo_bootimg_board" ]; then
    EXTRA_ARGS+=" --board $deviceinfo_bootimg_board"
fi

"$MKBOOTIMG" --kernel "$KERNEL" --header_version $deviceinfo_bootimg_header_version -o "$OUT" --os_version $deviceinfo_bootimg_os_version --os_patch_level $deviceinfo_bootimg_os_patch_level $EXTRA_ARGS
"$MKBOOTIMG" --ramdisk "$RAMDISK" --header_version $deviceinfo_bootimg_header_version -o "$(dirname "$OUT")/init_$(basename "$OUT")"
