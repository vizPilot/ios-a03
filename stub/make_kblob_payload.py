#!/usr/bin/env python3
"""Combina rd_loader.bin + rd_test_blob.bin y parchea offset/longitud.

Uso: python3 make_kblob_payload.py <loader.bin> <blob.bin> <salida.bin>
"""
import struct
import sys
from pathlib import Path

loader = bytearray(Path(sys.argv[1]).read_bytes())
blob = Path(sys.argv[2]).read_bytes()
out = sys.argv[3]

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

blob_off = (len(loader) + 7) // 8 * 8
loader[idx[0]:idx[0]+4] = struct.pack("<I", blob_off)
loader[idx[1]:idx[1]+4] = struct.pack("<I", len(blob))

payload = bytes(loader) + b"\0" * (blob_off - len(loader)) + blob
Path(out).write_bytes(payload)

print(f"loader : {len(loader)} bytes")
print(f"blob   : {len(blob)} bytes @ payload+{blob_off:#x}")
print(f"payload: {len(payload)} bytes -> {out}")
