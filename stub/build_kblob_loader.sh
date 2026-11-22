#!/bin/bash
# Loader con blob embebido en el payload del kernel. Ramdisk 100% stock.
set -e
cd /mnt/d/ios-a03/stub

echo "[1/5] compilar loader y blob de prueba"
make -f Makefile.loader clean all

echo "[2/5] combinar y parchear"
python3 make_kblob_payload.py rd_loader.bin rd_test_blob.bin /mnt/d/a03/kblob-payload.bin

echo "[3/5] inyectar en el kernel"
python3 inject_payload_append.py /mnt/d/a03/kblob-payload.bin /mnt/d/a03/kernel-kblob.img

echo "[4/5] construir boot.img con ramdisk stock"
bash build_boot.sh /mnt/d/a03/kernel-kblob.img /mnt/d/a03/kernel-kblob-boot.img

echo "[5/5] hash"
sha256sum /mnt/d/a03/kernel-kblob-boot.img
