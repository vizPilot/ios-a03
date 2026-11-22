#!/usr/bin/env python3
import gzip
import sys
from pathlib import Path

sys.path.insert(0, "/mnt/d/ios-a03/stub")
import cpio_tool

stock = Path("/mnt/d/ios-a03/stub/stock/ramdisk").read_bytes()
new = Path("/mnt/d/a03/ramdisk-rd.bin").read_bytes()

print("stock:", len(stock), "multi-miembro:", len(new))
print("primer miembro byte-idéntico:", new[:len(stock)] == stock)

raw = gzip.decompress(new)
print("descomprimido total:", len(raw))
entries, _ = cpio_tool.read_entries("/mnt/d/a03/ramdisk-rd.bin")
print("entradas:", [e["name"] for e in entries])
blob = next(e["content"] for e in entries if e["name"] == "xnu_payload.bin")
test = Path("/mnt/d/ios-a03/stub/rd_test_blob.bin").read_bytes()
print("blob coincide:", blob == test, "longitud:", len(blob))
