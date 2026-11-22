#!/usr/bin/env python3
"""Genera un Mach-O arm64 minimo con __TEXT + LC_UNIXTHREAD.

El codigo del entry se coloca en fileoff 0x4000 y su PC virtual es
link_base + 0x4000. El loader lo rebasara a KERN_PHYS + 0x4000.

Uso: python3 make_test_macho.py <stub.bin> <salida.macho>
"""
import struct
import sys
from pathlib import Path

code = Path(sys.argv[1]).read_bytes()
out = Path(sys.argv[2])

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
MH_EXECUTE = 2
LC_SEGMENT_64 = 0x19
LC_UNIXTHREAD = 0x05
ARM_THREAD_STATE64 = 6

LINK_BASE = 0xFFFFFFF007004000
FILEOFF = 0x4000
VMSIZE = 0x10000

# Mach-O bien formado: __TEXT.vmaddr = LINK_BASE corresponde a fileoff 0.
# El codigo vivo en fileoff 0x4000 tiene entonces direccion virtual
# LINK_BASE + 0x4000, que es exactamente el PC de LC_UNIXTHREAD.
segment = struct.pack(
    "<II16sQQQQIIII",
    LC_SEGMENT_64,
    72,
    b"__TEXT",
    LINK_BASE,
    VMSIZE,
    0,          # fileoff: importa, no puede ser 0x4000
    0,          # filesize: se rellena mas abajo con el tamano total
    7,      # maxprot
    5,      # initprot
    0,      # nsects
    0,      # flags
)

thread = bytearray(288)
struct.pack_into("<IIII", thread, 0, LC_UNIXTHREAD, 288, ARM_THREAD_STATE64, 68)
struct.pack_into("<Q", thread, 272, LINK_BASE + FILEOFF)   # PC
struct.pack_into("<Q", thread, 280, 0)                     # CPSR

sizeofcmds = len(segment) + len(thread)
header = struct.pack(
    "<8I",
    MH_MAGIC_64,
    CPU_TYPE_ARM64,
    0,
    MH_EXECUTE,
    2,              # ncmds
    sizeofcmds,
    0,              # flags
    0,              # reserved
)

macho = bytearray(FILEOFF + len(code))
macho[:len(header)] = header
pos = len(header)
macho[pos:pos + len(segment)] = segment
pos += len(segment)
macho[pos:pos + len(thread)] = thread
macho[FILEOFF:FILEOFF + len(code)] = code

# El segmento __TEXT cubre todo el archivo, asi que vmaddr+i -> fileoff+i.
struct.pack_into("<Q", macho, 32 + 48, len(macho))   # filesize @ segment+48
out.write_bytes(macho)

print(f"codigo   : {len(code)} bytes @ fileoff {FILEOFF:#x}")
print(f"link base: {LINK_BASE:#x}")
print(f"PC       : {LINK_BASE + FILEOFF:#x}")
print(f"Mach-O   : {len(macho)} bytes -> {out}")
