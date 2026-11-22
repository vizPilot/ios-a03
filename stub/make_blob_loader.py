#!/usr/bin/env python3
"""Construye el kernel con blob_loader.S + blob_kernel.S (sin binarios de Apple).

Uso (desde WSL):
  make -f Makefile SRC=blob_loader.S TARGET=blob_loader BASE=0x169e810 clean all
  make -f Makefile SRC=blob_kernel.S TARGET=blob_kernel BASE=0x92500000 clean all
  python3 make_blob_loader.py
  bash build_boot.sh /mnt/d/a03/kernel-blob-loader.img /mnt/d/a03/kernel-blob-loader-boot.img
"""
import struct
import sys
from pathlib import Path

STOCK = Path('/mnt/d/ios-a03/stub/stock/kernel')
LOADER = Path(sys.argv[3]) if len(sys.argv) > 3 else Path('/mnt/d/ios-a03/stub/blob_loader.bin')
BLOB = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/mnt/d/ios-a03/stub/blob_kernel.bin')
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path('/mnt/d/a03/kernel-blob-loader2.img')

PAYLOAD_VMA = 0x169E810
TRAILER_OFF = 0x1781800
BA_DST = 0x92000000
BLOB_DST = 0x92500000
CMDLINE = b'debug=0x8 kext-dev-mode=1\0'
PH = struct.pack('<I', 0xDEADBEEF)

stock = STOCK.read_bytes()
loader = bytearray(LOADER.read_bytes())
blob = BLOB.read_bytes()

assert len(stock) == PAYLOAD_VMA, len(stock)
assert loader.count(PH) == 2, loader.count(PH)

blob_off = (len(loader) + 7) // 8 * 8
idx = []
pos = 0
while True:
    i = loader.find(PH, pos)
    if i < 0:
        break
    idx.append(i)
    pos = i + 4
assert len(idx) == 2

loader[idx[0]:idx[0] + 4] = struct.pack('<I', blob_off)
loader[idx[1]:idx[1] + 4] = struct.pack('<I', len(blob))

kernel = bytearray(stock)
code0 = 0x14000000 | ((PAYLOAD_VMA >> 2) & 0x03FFFFFF)
struct.pack_into('<I', kernel, 0, code0)
kernel += loader
kernel += b'\0' * (blob_off - len(loader))
kernel += blob

assert len(kernel) < TRAILER_OFF, (len(kernel), TRAILER_OFF)
OUT.write_bytes(kernel)

# boot_args esperado: coincide con lo que construye el loader
ba = bytearray(1152)
struct.pack_into('<HH', ba, 0, 2, 2)
struct.pack_into('<Q', ba, 8, 0xfffffff007004000)
struct.pack_into('<Q', ba, 16, 0x80000000)
struct.pack_into('<Q', ba, 24, 0xfffff000)
struct.pack_into('<Q', ba, 1144, 0xfffff000)
ba[108:108 + len(CMDLINE)] = CMDLINE

checksum = 0
for i in range(0, len(ba), 8):
    checksum = (checksum + struct.unpack_from('<Q', ba, i)[0]) & 0xFFFFFFFFFFFFFFFF

print(f'OK: {OUT}')
print(f'  loader  : {len(loader)} bytes @ {PAYLOAD_VMA:#x}')
print(f'  blob    : {len(blob)} bytes @ payload+{blob_off:#x} -> {BLOB_DST:#x}')
print(f'  kernel  : {len(kernel)} bytes (trailer {TRAILER_OFF:#x})')
print(f'  code0   : {code0:#010x}')
print(f'  esperado en /proc/version: BL:{checksum:016x}:{BLOB_DST:016x}')
