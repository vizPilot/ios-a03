#!/usr/bin/env python3
import struct
from pathlib import Path

d = Path("/mnt/d/a03/kernel-macho.img").read_bytes()
base = 0x80000
# Los placeholders estan donde el entry los direcciona: buscar los 4 DEADBEEF
# parcheados leyendo el valor de los adr del desensamblado: 0x80..0x8c.
ph = [struct.unpack_from("<I", d, base + 0x80 + 4*i)[0] for i in range(4)]
print("placeholders @0x80:", [hex(x) for x in ph])
macho_off, macho_len, dtb_off, dtb_len = ph
print("macho:", hex(base+macho_off), macho_len)
print("dtb  :", hex(base+dtb_off), dtb_len)
assert dtb_len == 376049
assert d[base+dtb_off:base+dtb_off+4] == b"\xd0\x0d\xfe\xed"
assert d[base+macho_off:base+macho_off+4] == b"\xcf\xfa\xed\xfe"
print("OK: offsets y magic correctos en el Image")

# Comprobar que no quedo ningun 0xDEADBEEF sin parchear en el loader
loader_region = d[base:base+macho_off]
print("DEADBEEF sin parchear en loader:", loader_region.count(b"\xef\xbe\xad\xde"))
