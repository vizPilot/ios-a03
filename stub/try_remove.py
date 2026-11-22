#!/usr/bin/env python3
"""Busca una entrada pequena que se pueda quitar sin pasar de pagina."""
import gzip
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cpio_tool import read_entries, write_entries, new_entry

stock = "/mnt/d/ios-a03/stub/stock/ramdisk"
entries, _ = read_entries(stock)
limit = 364 * 2048
print("limit", limit)

names = [e["name"] for e in entries]
for drop in [None, "debug_ramdisk", "mnt", "proc", "sys", ".backup/.rmlist", ".backup"]:
    es = [e for e in entries if e["name"] != drop]
    ino = max(int(e["fields"][1], 16) for e in es) + 1
    idx = next(i for i, e in enumerate(es) if e["name"] == "TRAILER!!!")
    es.insert(idx, new_entry("X", b"X", ino))
    blob = write_entries(es)
    size = len(gzip.compress(blob, 9, mtime=0))
    print(f"drop={str(drop):18} size={size} ok={size <= limit}")
