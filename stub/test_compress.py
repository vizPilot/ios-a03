#!/usr/bin/env python3
import gzip
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cpio_tool import read_entries, write_entries, add

stock = "/mnt/d/ios-a03/stub/stock/ramdisk"
entries, raw = read_entries(stock)
blob = write_entries(entries)
print("raw", len(raw))
for lvl in (1, 6, 9):
    print("python gzip", lvl, len(gzip.compress(blob, compresslevel=lvl, mtime=0)))
    co = zlib.compressobj(lvl, zlib.DEFLATED, 31)
    print("zlib gzip ", lvl, len(co.compress(blob) + co.flush()))
for lvl in (6, 9):
    co = zlib.compressobj(lvl, zlib.DEFLATED, -15)
    print("zlib raw  ", lvl, len(co.compress(blob) + co.flush()) + 18)
