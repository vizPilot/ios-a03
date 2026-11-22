#!/usr/bin/env python3
"""Construye un Image ARM64 minimo con el loader y su blob.

Layout:
  0x000   header ARM64 (code0 = b 0x80000, text_offset = 0x80000)
  0x040   ... relleno de cerros hasta 0x80000
  0x80000 payload = synth_loader.bin + alineacion + blob

Uso: python3 build_synth_kernel.py <loader.bin> <blob.bin> <salida>
"""
import struct
import sys
from pathlib import Path

loader = bytearray(Path(sys.argv[1]).read_bytes())
blob = Path(sys.argv[2]).read_bytes()
out = Path(sys.argv[3])

PH = struct.pack("<I", 0xDEADBEEF)
idx = []
pos = 0
while True:
    i = loader.find(PH, pos)
    if i < 0:
        break
    idx.append(i)
    pos = i + 4
assert len(idx) == 2, f"se esperaban 2 placeholders, hay {len(idx)}"

TEXT_OFFSET = 0x80000
blob_off = (len(loader) + 7) // 8 * 8
loader[idx[0]:idx[0] + 4] = struct.pack("<I", blob_off)
loader[idx[1]:idx[1] + 4] = struct.pack("<I", len(blob))
payload = bytes(loader) + b"\0" * (blob_off - len(loader)) + blob

raw_size = TEXT_OFFSET + len(payload)
total = (raw_size + 2047) & ~2047

image = bytearray(total)
# code0: b 0x80000  ->  0x14000000 | (0x80000/4)
struct.pack_into("<I", image, 0x00, 0x14000000 | (TEXT_OFFSET // 4))
struct.pack_into("<I", image, 0x04, 0)
struct.pack_into("<Q", image, 0x08, TEXT_OFFSET)
struct.pack_into("<Q", image, 0x10, total)
struct.pack_into("<Q", image, 0x18, 0xA)      # flags del stock
image[0x38:0x3C] = b"ARMd"
image[TEXT_OFFSET:TEXT_OFFSET + len(payload)] = payload

out.write_bytes(image)
print(f"loader : {len(loader)} bytes")
print(f"blob   : {len(blob)} bytes @ payload+{blob_off:#x}")
print(f"payload: {len(payload)} bytes @ Image+{TEXT_OFFSET:#x}")
print(f"Image  : {total} bytes ({total//1024} KB), code0={struct.unpack_from('<I', image, 0)[0]:#010x}")
print(f"        image_size={total:#x}, magic={bytes(image[0x38:0x3c])!r}")
print(f"-> {out}")
