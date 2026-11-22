#!/usr/bin/env python3
"""Construye el kernel con el loader de bootargs_loader.S (sin DTB incrustado).

Uso (desde WSL):
  make -f Makefile SRC=bootargs_loader.S TARGET=bootargs_loader BASE=0x169e810
  python3 make_bootargs_loader.py
  bash build_boot.sh /mnt/d/a03/kernel-bootargs-loader.img /mnt/d/a03/kernel-bootargs-loader-boot.img
"""
import struct
from pathlib import Path

STOCK = Path('/mnt/d/ios-a03/stub/stock/kernel')
PAYLOAD = Path('/mnt/d/ios-a03/stub/bootargs_loader.bin')
OUT = Path('/mnt/d/a03/kernel-bootargs-loader.img')

PAYLOAD_VMA = 0x169E810
CMDLINE = b'debug=0x8 kext-dev-mode=1\0'

stock = STOCK.read_bytes()
payload = PAYLOAD.read_bytes()
assert len(stock) == PAYLOAD_VMA

kernel = bytearray(stock)
code0 = 0x14000000 | ((PAYLOAD_VMA >> 2) & 0x03FFFFFF)
struct.pack_into('<I', kernel, 0, code0)
kernel += payload
OUT.write_bytes(kernel)

# boot_args con deviceTreeP/length a cero: es lo que suma el payload
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
print(f'  payload : {len(payload)} bytes @ {PAYLOAD_VMA:#x}')
print(f'  kernel  : {len(kernel)} bytes')
print(f'  code0   : {code0:#010x}')
print(f'  esperado: BA:{checksum:016x}:D   (o :X si x0 no es el FDT)')
