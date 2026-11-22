#!/bin/bash
# Kernel sintetico + loader Mach-O + Mach-O sintetico de prueba.
set -e
cd /mnt/d/ios-a03/stub

echo "[1/5] compilar loader Mach-O y stub de prueba"
make -f Makefile.loader clean macho

echo "[2/5] generar Mach-O sintetico"
python3 make_test_macho.py macho_test_stub.bin /mnt/d/a03/test-kernelcache.macho

echo "[3/5] construir Image ARM64 minimo"
python3 build_synth_handoff.py macho_loader.bin \
    /mnt/d/a03/test-kernelcache.macho /mnt/d/a03/a03.dtb \
    /mnt/d/a03/kernel-macho.img

echo "[4/5] construir boot.img"
bash build_boot.sh /mnt/d/a03/kernel-macho.img /mnt/d/a03/kernel-macho-boot.img

echo "[5/5] hash"
sha256sum /mnt/d/a03/kernel-macho-boot.img
