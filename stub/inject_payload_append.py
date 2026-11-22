#!/usr/bin/env python3
"""Inyecta un payload al FINAL del kernel stock, sin sobrescribir codigo.

Uso:
  python3 inject_payload_append.py <payload.bin> <kernel-out.img>

El payload se enlaza en VMA = longitud del kernel stock (0x169e810).
code0 pasa a ser `b 0x169e810`, calculado como PC + (offset >> 2).
"""
import struct
import sys
from pathlib import Path

STOCK = Path('/mnt/d/ios-a03/stub/stock/kernel')
PAYLOAD_VMA = 0x169E810  # == len(stock kernel), verificado

payload = Path(sys.argv[1]).read_bytes()
out = Path(sys.argv[2])

kernel = bytearray(STOCK.read_bytes())
if len(kernel) != PAYLOAD_VMA:
    raise SystemExit(f'stock kernel inesperado: {len(kernel):#x}')

imm = (PAYLOAD_VMA >> 2) & 0x03FFFFFF
code0 = 0x14000000 | imm
struct.pack_into('<I', kernel, 0, code0)

kernel += payload
out.write_bytes(kernel)

print(f'OK: {out}')
print(f'  stock kernel : {len(STOCK.read_bytes())} bytes')
print(f'  payload      : {len(payload)} bytes @ {PAYLOAD_VMA:#x} (final del archivo)')
print(f'  code0        : {code0:#010x}  (b {PAYLOAD_VMA:#x} desde image_base)')
print(f'  total        : {len(kernel)} bytes')
