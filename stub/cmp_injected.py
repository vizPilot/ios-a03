import struct
from pathlib import Path

for n, p in [("STOCK", "stock/kernel"), ("INJECTED", "kernel-injected.img")]:
    b = Path(p).read_bytes()[:64]
    c0, c1, to, isz, fl = struct.unpack_from("<IIQQQ", b, 0)
    print(
        "%-9s code0=0x%08X code1=0x%08X text=0x%X size=0x%X flags=0x%X magic=%r"
        % (n, c0, c1, to, isz, fl, b[32:36])
    )
