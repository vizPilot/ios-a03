#!/usr/bin/env python3
"""Prueba variantes para que el CPIO con marcador quepa en la misma pagina."""
import gzip
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cpio_tool import read_entries, write_entries, new_entry

stock = "/mnt/d/ios-a03/stub/stock/ramdisk"
entries, _ = read_entries(stock)
base = write_entries(entries)
print("stock recompressed", len(gzip.compress(base, 9, mtime=0)), "page limit", 365 * 2048)

for name, content in [
    ("XNU_PROBE", b"XNU-PROBE-A03\n"),
    ("XNU_PROBE", b"X"),
    ("XNU_PROBE", b""),
    ("X", b"X"),
    ("P", b"P"),
]:
    ino = max(int(e["fields"][1], 16) for e in entries) + 1
    es = list(entries)
    idx = next(i for i, e in enumerate(es) if e["name"] == "TRAILER!!!")
    es.insert(idx, new_entry(name, content, ino))
    blob = write_entries(es)
    variants = {
        "gzip9": gzip.compress(blob, 9, mtime=0),
        "zlib31m9": None,
        "zlib31m8": None,
        "zlib31strat1": None,
    }
    co = zlib.compressobj(9, zlib.DEFLATED, 31, 9, zlib.Z_DEFAULT_STRATEGY)
    variants["zlib31m9"] = co.compress(blob) + co.flush()
    co = zlib.compressobj(9, zlib.DEFLATED, 31, 8, zlib.Z_DEFAULT_STRATEGY)
    variants["zlib31m8"] = co.compress(blob) + co.flush()
    co = zlib.compressobj(9, zlib.DEFLATED, 31, 8, zlib.Z_FILTERED)
    variants["zlib31strat1"] = co.compress(blob) + co.flush()
    sizes = " ".join(f"{k}={len(v)}" for k, v in variants.items())
    print(f"{name!r:12} {content!r:18} {sizes}")
