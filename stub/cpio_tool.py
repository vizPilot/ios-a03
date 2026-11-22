#!/usr/bin/env python3
"""Manipulador de CPIO newc que preserva metadata y entradas.

Uso:
  python3 cpio_tool.py extract <ramdisk.gz> <dir>
  python3 cpio_tool.py pack <dir> <output.gz>          # solo diagnostico
  python3 cpio_tool.py add <ramdisk.gz> <name> <output.gz>
"""
import gzip
import struct
import sys
from pathlib import Path

MAGIC = b"070701"
FIELDS = 13  # campos de 8 bytes despues del magic


def _hdr(fields):
    h = b"".join(fields)
    assert len(h) == 110
    return h


def read_entries(path):
    data = gzip.decompress(Path(path).read_bytes())
    pos = 0
    entries = []
    while pos + 110 <= len(data):
        h = data[pos:pos + 110]
        if h[:6] != MAGIC:
            raise ValueError(f"magic CPIO invalido en {pos}: {h[:6]!r}")
        fields = list(struct.unpack("6s" + "8s" * FIELDS, h))
        namesize = int(fields[12], 16)
        filesize = int(fields[7], 16)
        raw_name = data[pos + 110:pos + 110 + namesize]
        name = raw_name[:-1].decode(errors="replace")
        data_start = (pos + 110 + namesize + 3) & ~3
        content = data[data_start:data_start + filesize]
        entries.append({
            "fields": fields,
            "raw_name": raw_name,
            "name": name,
            "content": content,
        })
        pos = (data_start + filesize + 3) & ~3
    return entries, data


def write_entries(entries):
    out = bytearray()
    for e in entries:
        fields = list(e["fields"])
        fields[7] = f"{len(e['content']):08X}".encode()
        fields[12] = f"{len(e['raw_name']):08X}".encode()
        entry = bytearray(_hdr(fields))
        entry += e["raw_name"]
        while len(entry) % 4:
            entry += b"\0"
        entry += e["content"]
        while len(entry) % 4:
            entry += b"\0"
        out += entry
    return bytes(out)


def new_entry(name, content, ino, mode=0o100644):
    raw_name = name.encode() + b"\0"
    fields = [
        MAGIC,
        f"{ino:08X}".encode(),
        f"{mode:08X}".encode(),
        b"00000000",  # uid
        b"00000000",  # gid
        b"00000001",  # nlink
        b"00000000",  # mtime
        f"{len(content):08X}".encode(),
        b"00000000",  # devmajor
        b"00000000",  # devminor
        b"00000000",  # rdevmajor
        b"00000000",  # rdevminor
        f"{len(raw_name):08X}".encode(),
        b"00000000",  # check
    ]
    return {"fields": fields, "raw_name": raw_name, "name": name, "content": content}


def extract(ramdisk_gz, outdir):
    entries, _ = read_entries(ramdisk_gz)
    out = Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    for e in entries:
        name = e["name"]
        if name in ("", ".", "TRAILER!!!"):
            continue
        mode = int(e["fields"][2], 16)
        target = out / name.lstrip("/")
        if mode & 0o170000 == 0o040000 or name.endswith("/"):
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(e["content"])
    print(f"extraidos {len(entries)} entries a {outdir}")


def pack(indir, output_gz):
    """Empaqueta un directorio (solo archivos regulares); para diagnostico."""
    root = Path(indir)
    entries = []
    for ino, f in enumerate(sorted(root.rglob("*")), 1):
        if not f.is_file():
            continue
        rel = str(f.relative_to(root)).replace("\\", "/")
        entries.append(new_entry(rel, f.read_bytes(), ino))
    trailer = new_entry("TRAILER!!!", b"", 0, 0o00755)
    entries.append(trailer)
    Path(output_gz).write_bytes(gzip.compress(write_entries(entries), compresslevel=9))
    print(f"empaquetado {len(entries)} entries -> {output_gz}")


def add(ramdisk_gz, name, output_gz, content=None):
    entries, _ = read_entries(ramdisk_gz)
    ino = max(int(e["fields"][1], 16) for e in entries) + 1
    marker = new_entry(name, content or b"XNU-PROBE-A03\n", ino)
    idx = next((i for i, e in enumerate(entries) if e["name"] == "TRAILER!!!"), len(entries))
    entries.insert(idx, marker)
    blob = write_entries(entries)
    Path(output_gz).write_bytes(gzip.compress(blob, compresslevel=9, mtime=0))
    print(f"entradas={len(entries)} sin_comprimir={len(blob)} -> {output_gz}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "extract":
        extract(sys.argv[2], sys.argv[3])
    elif cmd == "pack":
        pack(sys.argv[2], sys.argv[3])
    elif cmd == "add":
        add(sys.argv[2], sys.argv[3], sys.argv[4],
            sys.argv[5].encode() if len(sys.argv) > 5 else None)
    else:
        raise SystemExit("uso: extract|pack|add")
