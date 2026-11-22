#!/usr/bin/env python3
"""Image ARM64 sintetico con handoff estilo _start.

Payload = loader + blob + DTB crudo. Cuatro palabras 0xDEADBEEF se parchean
con blob_off, blob_len, dtb_off, dtb_len (en ese orden).

Uso: python3 build_synth_handoff.py <loader.bin> <blob.bin> <dtb> <salida>
"""
import struct
import sys
from pathlib import Path

loader = bytearray(Path(sys.argv[1]).read_bytes())
blob = Path(sys.argv[2]).read_bytes()
dtb = Path(sys.argv[3]).read_bytes()
out = Path(sys.argv[4])

assert dtb[:4] == b"\xd0\x0d\xfe\xed", "el DTB no tiene magic big-endian"
totalsize = struct.unpack_from(">I", dtb, 4)[0]
assert totalsize == len(dtb), f"totalsize {totalsize} != archivo {len(dtb)}"

PH = struct.pack("<I", 0xDEADBEEF)
idx = []
pos = 0
while True:
    i = loader.find(PH, pos)
    if i < 0:
        break
    idx.append(i)
    pos = i + 4
assert len(idx) == 4, f"se esperaban 4 placeholders, hay {len(idx)}"

TEXT_OFFSET = 0x80000
align8 = lambda n: (n + 7) & ~7

blob_off = align8(len(loader))
dtb_off = align8(blob_off + len(blob))
loader[idx[0]:idx[0] + 4] = struct.pack("<I", blob_off)
loader[idx[1]:idx[1] + 4] = struct.pack("<I", len(blob))
loader[idx[2]:idx[2] + 4] = struct.pack("<I", dtb_off)
loader[idx[3]:idx[3] + 4] = struct.pack("<I", dtb_len := len(dtb))

payload = (bytes(loader)
           + b"\0" * (blob_off - len(loader))
           + blob
           + b"\0" * (dtb_off - blob_off - len(blob))
           + dtb)

raw = TEXT_OFFSET + len(payload)
total = (raw + 2047) & ~2047
image = bytearray(total)
struct.pack_into("<I", image, 0x00, 0x14000000 | (TEXT_OFFSET // 4))
struct.pack_into("<I", image, 0x04, 0)
struct.pack_into("<Q", image, 0x08, TEXT_OFFSET)
struct.pack_into("<Q", image, 0x10, total)
struct.pack_into("<Q", image, 0x18, 0xA)
image[0x38:0x3C] = b"ARMd"
image[TEXT_OFFSET:TEXT_OFFSET + len(payload)] = payload
out.write_bytes(image)

print(f"loader : {len(loader)} bytes, placeholders @ {[hex(i) for i in idx]}")
print(f"blob   : {len(blob)} bytes @ payload+{blob_off:#x}")
print(f"dtb    : {len(dtb)} bytes @ payload+{dtb_off:#x} (magic OK)")
print(f"payload: {len(payload)} bytes")
print(f"Image  : {total} bytes ({total//1024} KB)")
print(f"-> {out}")
