#!/bin/bash
set -ex

TMPDOWN=$(realpath $1)
KERNEL_OBJ=$(realpath $2)
OUT=$(realpath $3)
INSTALL_MOD_PATH="$(realpath $4)"

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

# Create ramdisk for vendor_boot.img
if [ -d "$HERE/vendor-ramdisk-overlay" ]; then
    VENDOR_RAMDISK="$TMPDOWN/ramdisk-vendor_boot.img"
    rm -rf "$TMPDOWN/vendor-ramdisk"
    mkdir -p "$TMPDOWN/vendor-ramdisk"
    cd "$TMPDOWN/vendor-ramdisk"

    if [[ -f "$HERE/vendor-ramdisk-overlay/lib/modules/modules.load" && "$deviceinfo_kernel_disable_modules" != "true" ]]; then
        item_in_array() { local item match="$1"; shift; for item; do [ "$item" = "$match" ] && return 0; done; return 1; }
        modules_dep="$(find "$INSTALL_MOD_PATH"/ -type f -name modules.dep)"
        modules="$(dirname "$modules_dep")" # e.g. ".../lib/modules/5.10.110-gb4d6c7a2f3a6"
        modules_len=${#modules} # e.g. 105
        all_modules="$(find "$modules" -type f -name "*.ko*")"
        module_files=("$modules/modules.alias" "$modules/modules.dep" "$modules/modules.softdep")
        set +x
        while read -r mod; do
            mod_path="$(echo -e "$all_modules" | grep "/$mod" || true)" # ".../kernel/.../mod.ko"
            if [ -z "$mod_path" ]; then
                echo "Missing the module file $mod included in modules.load"
                continue
            fi
            mod_path="${mod_path:$((modules_len+1))}" # drop absolute path prefix
            dep_paths="$(sed -n "s|^$mod_path: ||p" "$modules_dep")"
            for mod_file in $mod_path $dep_paths; do # e.g. "kernel/.../mod.ko"
                item_in_array "$modules/$mod_file" "${module_files[@]}" && continue # skip over already processed modules
                module_files+=("$modules/$mod_file")
            done
        done < <(cat "$HERE/vendor-ramdisk-overlay/lib/modules/modules.load"* | sort | uniq)
        set -x
        mkdir -p "$TMPDOWN/vendor-ramdisk/lib/modules"
        cp "${module_files[@]}" "$TMPDOWN/vendor-ramdisk/lib/modules"

        # rewrite modules.dep for GKI /lib/modules/*.ko structure
        set +x
        while read -r line; do
            printf '/lib/modules/%s:' "$(basename ${line%:*})"
            deps="${line#*:}"
            if [ "$deps" ]; then
                for m in $(basename -a $deps); do
                    printf ' /lib/modules/%s' "$m"
                done
            fi
            echo
        done < "$modules/modules.dep" | tee "$TMPDOWN/vendor-ramdisk/lib/modules/modules.dep"
        set -x
    fi

    cp -r "$HERE/vendor-ramdisk-overlay"/* "$TMPDOWN/vendor-ramdisk"

    find . | cpio -o -H newc | $COMPRESSION_CMD > "$VENDOR_RAMDISK"
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

MKBOOTIMG="$TMPDOWN/android_system_tools_mkbootimg/mkbootimg.py"
EXTRA_VENDOR_ARGS=""

EXTRA_VENDOR_ARGS+=" --base $deviceinfo_flash_offset_base --kernel_offset $deviceinfo_flash_offset_kernel --ramdisk_offset $deviceinfo_flash_offset_ramdisk --tags_offset $deviceinfo_flash_offset_tags --pagesize $deviceinfo_flash_pagesize --dtb $DTB --dtb_offset $deviceinfo_flash_offset_dtb"

if [ "$deviceinfo_bootimg_header_version" -eq 4 ]; then
    if [ -n "$deviceinfo_vendor_bootconfig_path" ]; then
        EXTRA_VENDOR_ARGS+=" --vendor_bootconfig ${HERE}/$deviceinfo_vendor_bootconfig_path"
    fi
fi

if [ -n "$VENDOR_RAMDISK" ]; then
    VENDOR_RAMDISK_ARGS=()
    if [ "$deviceinfo_bootimg_header_version" -eq 3 ]; then
        VENDOR_RAMDISK_ARGS=(--vendor_ramdisk "$VENDOR_RAMDISK")
    else
        VENDOR_RAMDISK_ARGS=(--ramdisk_type platform --ramdisk_name '' --vendor_ramdisk_fragment "$VENDOR_RAMDISK")
    fi
    "$MKBOOTIMG" "${VENDOR_RAMDISK_ARGS[@]}" --vendor_cmdline "$deviceinfo_kernel_cmdline" --header_version $deviceinfo_bootimg_header_version --vendor_boot "$(dirname "$OUT")/vendor_$(basename "$OUT")" $EXTRA_VENDOR_ARGS
fi
