#!/usr/bin/env python3
"""Genera kernel.img con cabecera ARM64 Image y payload en 0x80000.

Equivalente a make_kernel_image.ps1 para WSL/Linux.

IMPORTANTE: la cabecera arm64_image_header es de 112 bytes; el magic
"ARMd" va en 0x40, NO en 0x20. copy de la layout real del kernel stock.
"""
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
payload_name = sys.argv[1] if len(sys.argv) > 1 else "uart_hello.bin"
output_name = sys.argv[2] if len(sys.argv) > 2 else "kernel.img"
text_offset = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x80000

payload = (HERE / payload_name).read_bytes()
total = text_offset + len(payload)
img = bytearray(total)

# AArch64 B <text_offset>
imm = (text_offset >> 2) & 0x03FFFFFF
code0 = 0x14000000 | imm
code1 = 0xD503201F  # NOP

# struct arm64_image_header (112 bytes)
struct.pack_into("<I", img, 0, code0)                 # code0
struct.pack_into("<I", img, 4, code1)                 # code1
struct.pack_into("<Q", img, 8, text_offset)           # text_offset
struct.pack_into("<Q", img, 16, total)                # image_size
struct.pack_into("<Q", img, 24, 0)                    # flags
struct.pack_into("<Q", img, 32, 0)                    # res1
struct.pack_into("<Q", img, 40, 0)                    # res2
struct.pack_into("<Q", img, 48, 0)                    # res3
struct.pack_into("<I", img, 56, 0x644D5241)           # magic "ARMd" @ 0x38
struct.pack_into("<I", img, 60, 0)                    # res4

img[text_offset:text_offset + len(payload)] = payload
(HERE / output_name).write_bytes(img)

print(f"OK: {output_name}")
print(f"  payload : {len(payload)} bytes")
print(f"  offset  : 0x{text_offset:X}")
print(f"  total   : {total} bytes (0x{total:X})")
print(f"  code0   : 0x{code0:08X}")
