#!/bin/bash
# Kernel sintetico con loader + blob magenta. Ramdisk y DTB stock.
set -e
cd /mnt/d/ios-a03/stub

echo "[1/4] compilar loader sintetico y blob"
make -f Makefile.loader clean synth

echo "[2/4] construir Image ARM64 minimo"
python3 build_synth_kernel.py synth_loader.bin synth_test_blob.bin /mnt/d/a03/kernel-synth.img

echo "[3/4] construir boot.img"
bash build_boot.sh /mnt/d/a03/kernel-synth.img /mnt/d/a03/kernel-synth-boot.img

echo "[4/4] hash"
sha256sum /mnt/d/a03/kernel-synth-boot.img
