#!/bin/bash
# Construye boot.img con loader desde ramdisk + blob de prueba.
set -e
cd /mnt/d/ios-a03/stub

echo "[1/4] compilar loader y blob de prueba"
make -f Makefile.loader clean all

echo "[2/4] añadir blob al ramdisk"
python3 make_rd_ramdisk.py stock/ramdisk rd_test_blob.bin /mnt/d/a03/ramdisk-rd.bin

echo "[3/4] inyectar loader al final del kernel"
python3 inject_payload_append.py rd_loader.bin /mnt/d/a03/kernel-rd-loader.img

echo "[4/4] construir boot.img con ramdisk modificado"
bash build_boot.sh /mnt/d/a03/kernel-rd-loader.img \
    /mnt/d/a03/kernel-rd-loader-boot.img /mnt/d/a03/ramdisk-rd.bin

sha256sum /mnt/d/a03/kernel-rd-loader-boot.img
