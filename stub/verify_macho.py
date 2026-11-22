#!/usr/bin/env python3
import struct
from pathlib import Path

p = Path("/mnt/d/a03/test-kernelcache.macho")
d = p.read_bytes()
magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, res = struct.unpack_from("<8I", d, 0)
print("magic       :", hex(magic))
print("cputype     :", hex(cputype))
print("ncmds       :", ncmds, "sizeofcmds", sizeofcmds)
assert magic == 0xFEEDFACF and cputype == 0x0100000C
assert ncmds == 2

off = 32
link_base = None
entry_virt = None
for _ in range(ncmds):
    cmd, sz = struct.unpack_from("<II", d, off)
    if cmd == 0x19:
        name = d[off + 8:off + 24].split(b"\0")[0].decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<4Q", d, off + 24)
        print("segment     :", name, hex(vmaddr), hex(vmsize), hex(fileoff), hex(filesize))
        if name == "__TEXT":
            link_base = vmaddr
    elif cmd == 0x05:
        flavor, count = struct.unpack_from("<II", d, off + 8)
        entry_virt = struct.unpack_from("<Q", d, off + 272)[0]
        print("thread      : flavor", flavor, "count", count, "pc", hex(entry_virt))
    off += sz
assert off == 32 + sizeofcmds

KERN_PHYS = 0xA2000000
entry_phys = KERN_PHYS + (entry_virt - link_base)
print("entry fisico:", hex(entry_phys))
assert entry_phys == 0xA2004000
assert fileoff == 0 and filesize == len(d), (hex(fileoff), hex(filesize))
code_at = d[0x4000:0x4004]
print("codigo en entry:", code_at.hex())
assert code_at != b"\x00\x00\x00\x00", "el entry esta a cero"
print("OK: loader saltaria a 0xA2004000 con codigo real")
