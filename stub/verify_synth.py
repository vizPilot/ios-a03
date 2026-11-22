#!/usr/bin/env python3
import struct
from pathlib import Path

p = Path("/mnt/d/a03/kernel-synth.img")
d = p.read_bytes()
code0, code1, text_off, image_size, flags = struct.unpack_from("<IIQQQ", d, 0)
magic = d[0x38:0x3c]
imm = code0 & 0x03FFFFFF
print("tamano archivo :", len(d), hex(len(d)))
print("code0          :", hex(code0), "-> op", hex(code0 >> 26), "dest", hex(imm * 4))
print("code1          :", hex(code1))
print("text_offset    :", hex(text_off))
print("image_size     :", hex(image_size), "== archivo:", image_size == len(d))
print("flags          :", hex(flags))
print("magic          :", magic)
print("payload @0x80000:", d[0x80000:0x80010].hex(" "))
assert code0 >> 26 == 0b000101, "code0 no es un B"
assert imm * 4 == 0x80000
assert text_off == 0x80000
assert magic == b"ARMd"
assert image_size == len(d)
print("OK: header consistente")
