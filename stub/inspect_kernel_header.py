#!/usr/bin/env python3
import struct
from pathlib import Path

k = Path("/mnt/d/ios-a03/stub/stock/kernel").read_bytes()
print("longitud:", len(k), hex(len(k)))
print("code0:", hex(struct.unpack_from("<I", k, 0)[0]))
print("code1:", hex(struct.unpack_from("<I", k, 4)[0]))
print("text_offset:", hex(struct.unpack_from("<Q", k, 8)[0]))
print("image_size:", hex(struct.unpack_from("<Q", k, 16)[0]))
print("flags:", hex(struct.unpack_from("<Q", k, 24)[0]))
for off in (0x30, 0x38, 0x40, 0x48, 0x50):
    print(f"@{off:#x}:", k[off:off+16])
print("magic ARM64 en 0x38:", k[0x38:0x3c])
