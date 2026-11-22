#!/usr/bin/env python3
"""Localiza linux_proc_banner y linux_banner en el kernel stock."""
from pathlib import Path

d = Path('/mnt/d/ios-a03/stub/stock/kernel').read_bytes()
for needle in (b'%s version %s', b'version %s', b'Linux version'):
    print('===', needle)
    pos = 0
    while True:
        i = d.find(needle, pos)
        if i < 0:
            break
        s = d[i:i + 160].split(b'\0')[0]
        print(hex(i), repr(s[:150]))
        pos = i + 1
