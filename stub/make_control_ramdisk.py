#!/usr/bin/env python3
"""Genera un ramdisk de control con un marcador dentro del mismo stream gzip.

Mantiene todas las entradas del stock excepto `.backup/.rmlist` (la lista de
limpieza de Magisk, innecesaria para el test) y anade `/X` con contenido `X`.
El resultado cabe en la misma pagina de 2048 bytes que el ramdisk stock.
"""
import gzip
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cpio_tool import read_entries, write_entries, new_entry

STOCK = "/mnt/d/ios-a03/stub/stock/ramdisk"
DROP = ".backup/.rmlist"


def main(out):
    entries, _ = read_entries(STOCK)
    entries = [e for e in entries if e["name"] != DROP]
    ino = max(int(e["fields"][1], 16) for e in entries) + 1
    idx = next(i for i, e in enumerate(entries) if e["name"] == "TRAILER!!!")
    entries.insert(idx, new_entry("X", b"X", ino))
    blob = write_entries(entries)
    data = gzip.compress(blob, compresslevel=9, mtime=0)
    Path(out).write_bytes(data)
    print(f"entries={len(entries)} raw={len(blob)} gzip={len(data)} -> {out}")


if __name__ == "__main__":
    main(sys.argv[1])
