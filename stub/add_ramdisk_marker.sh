#!/bin/bash
# Añade un archivo /XNU_PROBE al ramdisk (como hace Magisk) sin tocar el kernel.
set -e
cd /mnt/d/ios-a03/stub
rm -rf /tmp/rdwork
mkdir -p /tmp/rdwork
cd /tmp/rdwork
gzip -dc /mnt/d/ios-a03/stub/stock/ramdisk | cpio -idm --quiet
echo "XNU-PROBE-A03" > XNU_PROBE
find . | cpio -o -H newc --quiet | gzip -9 > /tmp/ramdisk-marked.img
ls -l /tmp/ramdisk-marked.img
sha256sum /tmp/ramdisk-marked.img
