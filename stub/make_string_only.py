#!/usr/bin/env python3
"""Parchea solo la cadena de /proc/version, sin tocar code0.

Prueba de control: si /proc/version muestra XNU, el kernel flasheado es el
nuestro y el offset 0x1062248 es correcto. Entonces el payload no corrio
porque LK ignora code0.
"""
from pathlib import Path

stock = Path('/mnt/d/ios-a03/stub/stock/kernel').read_bytes()
OUT = Path('/mnt/d/a03/kernel-string-only.img')
OFF = 0x1062248

k = bytearray(stock)
assert k[OFF:OFF + 5] == b'Linux', k[OFF:OFF + 16]
k[OFF:OFF + 5] = b'XNU  '
OUT.write_bytes(k)

print(f'OK: {OUT}')
print(f'  offset {OFF:#x}: {bytes(k[OFF:OFF+32]).split(bytes([0]))[0]!r}')
print(f'  code0 intacto: {int.from_bytes(k[0:4], "little"):#010x}')
