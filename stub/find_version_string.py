#!/usr/bin/env python3
"""Localiza la cadena 'Linux version' en el kernel stock."""
from pathlib import Path

d = Path('/mnt/d/ios-a03/stub/stock/kernel').read_bytes()
needle = b'Linux version'
pos = 0
while True:
    i = d.find(needle, pos)
    if i < 0:
        break
    print(hex(i), d[i:i + 96].split(b'\0')[0].decode('ascii', 'replace'))
    pos = i + 1
