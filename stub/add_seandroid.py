#!/usr/bin/env python3
"""Añade el trailer SEANDROIDENFORCE + padding a 64MB, como el boot.img stock."""
import sys
from pathlib import Path

TARGET = 64 * 1024 * 1024
TRAILER = b"SEANDROIDENFORCE"

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
data = src.read_bytes()

out = bytearray(TARGET)
out[:len(data)] = data
off = len(data)
out[off:off + len(TRAILER)] = TRAILER

dst.write_bytes(out)
print(f"OK: {dst}")
print(f"  input  : {len(data)} bytes")
print(f"  trailer: {TRAILER.decode()} @ 0x{off:X}")
print(f"  output : {len(out)} bytes")
