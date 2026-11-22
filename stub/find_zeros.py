#!/usr/bin/env python3
"""Busca regiones grandes de ceros en el kernel stock para inyectar un payload."""
from pathlib import Path

p = Path('/mnt/d/ios-a03/stub/stock/kernel')
d = p.read_bytes()
print('size', len(d), hex(len(d)))

runs = []
start = None
for i, b in enumerate(d):
    if b == 0:
        if start is None:
            start = i
    else:
        if start is not None and i - start >= 64:
            runs.append((start, i - start))
        start = None
if start is not None and len(d) - start >= 64:
    runs.append((start, len(d) - start))

runs.sort(key=lambda r: -r[1])
for s, n in runs[:25]:
    print(hex(s), hex(n))
