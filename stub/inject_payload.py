#!/usr/bin/env python3
"""Inyecta nuestro payload en el kernel stock manteniendo su cabecera ARM64.

El kernel stock tiene:
  text_offset = 0x80000  -> el kernel real empieza en ese offset
  code0 = B 0x4800000   -> salto al codigo de descompresion

Estrategia:
  - Copiar el kernel stock entero (cabecera, flags, firma interna, etc.)
  - Escribir nuestro payload en offset 0x80000
  - Cambiar code0 para que salte a 0x80000 (nuestro payload)
  - Mantener code1, flags, image_size y todo lo demas igual
"""
import struct
from pathlib import Path
import sys

STOCK = Path("/mnt/d/ios-a03/stub/stock/kernel")
payload_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("uart_hello.bin")
out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("kernel-injected.img")

payload = payload_path.read_bytes()
kernel = bytearray(STOCK.read_bytes())

TEXT_OFF = 0x80000
if len(kernel) < TEXT_OFF + len(payload):
    raise SystemExit("kernel stock demasiado corto")

# B 0x80000: imm26 = text_offset >> 2
imm = (TEXT_OFF >> 2) & 0x03FFFFFF
code0 = 0x14000000 | imm
struct.pack_into("<I", kernel, 0, code0)

# Inyectar payload en text_offset
kernel[TEXT_OFF:TEXT_OFF + len(payload)] = payload

out_path.write_bytes(kernel)
print(f"OK: {out_path}")
print(f"  stock kernel : {len(kernel)} bytes")
print(f"  payload      : {len(payload)} bytes @ 0x{TEXT_OFF:X}")
print(f"  code0        : 0x{code0:08X}")
