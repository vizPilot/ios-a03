#!/usr/bin/env python3
"""Control: ramdisk stock sin .backup/init.xz, sin blob ni loader."""
import gzip
import sys
from pathlib import Path

sys.path.insert(0, "/mnt/d/ios-a03/stub")
import cpio_tool

entries, _ = cpio_tool.read_entries("/mnt/d/ios-a03/stub/stock/ramdisk")
entries = [e for e in entries if e["name"] != ".backup/init.xz"]
raw = cpio_tool.write_entries(entries)
out = "/mnt/d/a03/ramdisk-control-nobackup.bin"
Path(out).write_bytes(gzip.compress(raw, compresslevel=9, mtime=0))
print(f"entradas={len(entries)} sin_comprimir={len(raw)} -> {out}")
