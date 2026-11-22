#!/usr/bin/env python3
"""List entries in a gzip-compressed newc CPIO archive."""
import gzip
import struct
import sys


def main(path):
    data = gzip.decompress(open(path, "rb").read())
    pos = 0
    total = 0
    while pos + 110 <= len(data):
        h = data[pos:pos + 110]
        if h[:6] != b"070701":
            print("stop at", pos, "magic", h[:6])
            break
        f = struct.unpack("6s" + "8s" * 13, h)
        mode = int(f[2], 16)
        namesize = int(f[12], 16)
        size = int(f[7], 16)
        name = data[pos + 110:pos + 110 + namesize - 1].decode(errors="replace")
        ds = (pos + 110 + namesize + 3) & ~3
        print(f"{mode:08o} {size:8d} {name}")
        total += 1
        pos = (ds + size + 3) & ~3
    print("entries", total, "bytes", pos, "len", len(data))


if __name__ == "__main__":
    main(sys.argv[1])
