#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

for label, path in [("stock/dtb", "/mnt/d/ios-a03/stub/stock/dtb"),
                    ("a03.dtb", "/mnt/d/a03/a03.dtb")]:
    p = Path(path)
    if not p.exists():
        print(label, "no existe")
        continue
    d = p.read_bytes()
    magic, totalsize, off_struct, off_strings, off_rsvmap, version = struct.unpack_from(">6I", d, 0)
    print(f"{label}: archivo={len(d)} magic={magic:#010x} totalsize={totalsize}"
          f" padding={len(d)-totalsize}")
    print(f"   off_struct={off_struct} off_strings={off_strings}"
          f" off_rsvmap={off_rsvmap} version={version}")
    tail = d[totalsize:]
    nz = sum(1 for b in tail if b != 0)
    print(f"   bytes no cero en padding: {nz}")
