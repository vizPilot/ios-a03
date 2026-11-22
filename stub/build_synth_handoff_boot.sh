#!/bin/bash
# Kernel sintetico con boot_args + FDT + blob. Ramdisk/DTB stock en boot.img.
set -e
cd /mnt/d/ios-a03/stub

echo "[1/4] compilar loader de handoff y blob de validacion"
make -f Makefile.loader clean handoff

echo "[2/4] construir Image ARM64 minimo"
python3 build_synth_handoff.py handoff_loader.bin handoff_blob.bin \
    /mnt/d/a03/a03.dtb /mnt/d/a03/kernel-handoff.img

echo "[3/4] construir boot.img"
bash build_boot.sh /mnt/d/a03/kernel-handoff.img /mnt/d/a03/kernel-handoff-boot.img

echo "[4/4] hash"
sha256sum /mnt/d/a03/kernel-handoff-boot.img
