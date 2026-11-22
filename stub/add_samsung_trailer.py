#!/usr/bin/env python3
"""Añade el trailer Samsung completo en la misma posición que el stock.

El boot.img stock tiene:
  [0x00000000 .. 0x1781800)  contenido util (kernel + ramdisk + dtb)
  [0x1781800 .. 0x4000000)   SEANDROIDENFORCE + SignerVer02 + firma + padding

Este script coloca la cola del stock en 0x1781800, rellenando con ceros
si el boot.img experimenta es mas corto.
"""
import sys
from pathlib import Path

STOCK = Path("/mnt/d/a03/boot.img")
TRAILER_OFF = 0x1781800

stock = STOCK.read_bytes()
tail = stock[TRAILER_OFF:]

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
data = src.read_bytes()
if len(data) > TRAILER_OFF:
    raise SystemExit(f"input demasiado grande: {len(data)} > {TRAILER_OFF}")

out = bytearray(len(stock))
out[:len(data)] = data
out[TRAILER_OFF:] = tail
dst.write_bytes(out)
print(f"OK: {dst}")
print(f"  input  : {len(data)} bytes")
print(f"  trailer: 0x{TRAILER_OFF:X}")
print(f"  output : {len(out)} bytes")
