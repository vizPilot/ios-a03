#!/bin/bash
# Reconstruye un boot.img con los parametros del stock y añade el trailer Samsung.
# Uso: build_boot.sh <kernel> <salida.img> [ramdisk]
set -e
KERNEL="$1"
OUT="$2"
RAMDISK="${3:-stock/ramdisk}"
TMP="/tmp/ctrl-boot.img"
cd /mnt/d/ios-a03/stub

mkbootimg \
  --kernel "$KERNEL" \
  --ramdisk "$RAMDISK" \
  --dtb stock/dtb \
  --cmdline "console=ttyS1,115200n8" \
  --base 0x0 \
  --kernel_offset 0x8000 \
  --ramdisk_offset 0x01000000 \
  --tags_offset 0x100 \
  --dtb_offset 0x1f00000 \
  --os_version 11.0.0 \
  --os_patch_level 2025-08 \
  --board SRPUI23B009 \
  --pagesize 2048 \
  --header_version 2 \
  -o "$TMP"

python3 add_samsung_trailer.py "$TMP" "$OUT"
sha256sum "$OUT"
