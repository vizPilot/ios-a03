#!/usr/bin/env python3
import struct
from pathlib import Path

d = Path("/mnt/d/a03/kernel-handoff.img").read_bytes()
base = 0x80000
ph = [struct.unpack_from("<I", d, base + 0x60 + 4 * i)[0] for i in range(4)]
print("placeholders parcheados:", [hex(x) for x in ph])
blob_off, blob_len, dtb_off, dtb_len = ph
print("blob @", hex(base + blob_off), "len", blob_len)
print("dtb  @", hex(base + dtb_off), "len", dtb_len)
assert dtb_len == 376049
assert d[base + dtb_off:base + dtb_off + 4] == b"\xd0\x0d\xfe\xed"
assert blob_len == 216

# CommandLine del blob de validacion debe leer 'd' en boot_args+108
code0 = struct.unpack_from("<I", d, 0)[0]
print("code0:", hex(code0), "dest:", hex((code0 & 0x03FFFFFF) * 4))
print("magic:", d[0x38:0x3c])
print("OK: imagen consistente")
