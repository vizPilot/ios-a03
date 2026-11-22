#!/usr/bin/env python3
import gzip
import sys
from pathlib import Path

sys.path.insert(0, "/mnt/d/ios-a03/stub")
import cpio_tool

stock = Path("/mnt/d/ios-a03/stub/stock/ramdisk").read_bytes()
entries, raw = cpio_tool.read_entries("/mnt/d/ios-a03/stub/stock/ramdisk")

def page(n):
    return (n + 2047) & ~2047

print("stock: comprimido", len(stock), "pagina", page(len(stock)))
print("stock re-comprimido mtime=0:", len(gzip.compress(raw, compresslevel=9, mtime=0)))
print("stock re-comprimido mtime=None:", len(gzip.compress(raw, compresslevel=9)))
print()

variants = {}
variants["recomprimido"] = gzip.compress(raw, compresslevel=9, mtime=0)

con_blob = [e for e in entries]
ino = max(int(e["fields"][1], 16) for e in con_blob) + 1
blob = Path("/mnt/d/ios-a03/stub/rd_test_blob.bin").read_bytes()
con_blob.insert(-1, cpio_tool.new_entry("xnu_payload.bin", blob, ino))
variants["con blob nombre largo"] = gzip.compress(cpio_tool.write_entries(con_blob), compresslevel=9, mtime=0)

con_blob2 = [e for e in entries]
con_blob2.insert(-1, cpio_tool.new_entry("x", blob, ino))
variants["con blob nombre corto"] = gzip.compress(cpio_tool.write_entries(con_blob2), compresslevel=9, mtime=0)

sin_backup = [e for e in entries if e["name"] != ".backup/init.xz"]
sin_backup.insert(-1, cpio_tool.new_entry("x", blob, ino))
variants["sin backup + blob corto"] = gzip.compress(cpio_tool.write_entries(sin_backup), compresslevel=9, mtime=0)

for k, v in variants.items():
    print(f"{k:28s} {len(v):8d} pagina {page(len(v)):8d} delta vs stock {len(v)-len(stock):+d}")
