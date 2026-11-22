#!/usr/bin/env python3
"""Control: añade un comentario al fstab del ramdisk.

fstab permanece en rootfs despues de que Magisk limpie `.backup`, asi que es
un marcador legible sin depender de entradas nuevas.
"""
import gzip
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cpio_tool import read_entries, write_entries

STOCK = "/mnt/d/ios-a03/stub/stock/ramdisk"
TARGET = "fstab.ums9230_25c10"
MARK = b"\n# X\n"


def main(out):
    entries, _ = read_entries(STOCK)
    found = False
    for e in entries:
        if e["name"] == TARGET:
            e["content"] = e["content"].rstrip(b"\n") + MARK
            found = True
    if not found:
        raise SystemExit(f"no existe {TARGET}")
    blob = write_entries(entries)
    data = gzip.compress(blob, compresslevel=9, mtime=0)
    Path(out).write_bytes(data)
    print(f"entries={len(entries)} raw={len(blob)} gzip={len(data)} -> {out}")


if __name__ == "__main__":
    main(sys.argv[1])
