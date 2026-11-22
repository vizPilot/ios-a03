#!/usr/bin/env python3
"""Ramdisk multi-miembro: stock intacto + segundo miembro gzip con el blob.

El primer miembro gzip es byte-idéntico al ramdisk stock, así que Magisk y
Android arrancan igual. El loader escanea la memoria descomprimida, pasa por
el TRAILER!!! del primer CPIO y encuentra el segundo CPIO con xnu_payload.bin.

Uso: python3 make_rd_ramdisk.py <ramdisk.gz> <blob.bin> <salida.gz>
"""
import gzip
import sys
from pathlib import Path

sys.path.insert(0, "/mnt/d/ios-a03/stub")
import cpio_tool

stock_gz = Path(sys.argv[1]).read_bytes()
blob = Path(sys.argv[2]).read_bytes()
out = sys.argv[3]

second = [cpio_tool.new_entry("xnu_payload.bin", blob, 1),
          cpio_tool.new_entry("TRAILER!!!", b"", 0, 0o00755)]
second_raw = cpio_tool.write_entries(second)
second_gz = gzip.compress(second_raw, compresslevel=9, mtime=0)

result = stock_gz + second_gz
Path(out).write_bytes(result)

page = (len(result) + 2047) & ~2047
print(f"stock        : {len(stock_gz)} bytes")
print(f"2o miembro   : {len(second_gz)} bytes ({len(second_raw)} sin comprimir)")
print(f"total        : {len(result)} bytes -> pagina {page}")
print(f"margen pagina: {745472 - len(result)} bytes")
print(f"blob         : {len(blob)} bytes -> {out}")
