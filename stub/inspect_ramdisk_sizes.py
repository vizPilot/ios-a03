#!/usr/bin/env python3
import gzip
import sys
from pathlib import Path

sys.path.insert(0, "/mnt/d/ios-a03/stub")
import cpio_tool

for label, path in [("stock", "/mnt/d/ios-a03/stub/stock/ramdisk"),
                    ("nuevo", "/mnt/d/a03/ramdisk-rd.bin")]:
    raw = Path(path).read_bytes()
    print(label, "comprimido", len(raw), "sin comprimir", len(gzip.decompress(raw)))

entries, _ = cpio_tool.read_entries("/mnt/d/ios-a03/stub/stock/ramdisk")
print("entradas", len(entries))
for e in sorted(entries, key=lambda y: -len(y["content"]))[:15]:
    print(len(e["content"]), e["name"])
