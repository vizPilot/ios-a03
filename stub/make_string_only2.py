#!/usr/bin/env python3
"""Control: parchea linux_banner y linux_proc_banner, sin tocar code0.

- linux_banner      @ 0x1062248 -> "XNU   version ..." (se ve en dmesg)
- linux_proc_banner @ 0x10623a0 -> "XN version ..."    (se ve en /proc/version)
"""
from pathlib import Path

stock = Path('/mnt/d/ios-a03/stub/stock/kernel').read_bytes()
OUT = Path('/mnt/d/a03/kernel-string-only2.img')
BANNER = 0x1062248
PROC = 0x10623A0

k = bytearray(stock)
assert k[BANNER:BANNER + 5] == b'Linux'
assert k[PROC:PROC + 2] == b'%s'
k[BANNER:BANNER + 5] = b'XNU  '
k[PROC:PROC + 2] = b'XN'
OUT.write_bytes(k)

print(f'OK: {OUT}')
print(f'  dmesg  : {bytes(k[BANNER:BANNER+40]).split(bytes([0]))[0]!r}')
print(f'  proc   : {bytes(k[PROC:PROC+40]).split(bytes([0]))[0]!r}')
print(f'  code0 intacto: {int.from_bytes(k[0:4], "little"):#010x}')
