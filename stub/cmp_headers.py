from pathlib import Path
import struct

for name, path in [
    ("STOCK", "/mnt/d/ios-a03/stub/stock/kernel"),
    ("OURS", "/mnt/d/ios-a03/stub/kernel-probe2.img"),
]:
    b = Path(path).read_bytes()[:64]
    print(f"=== {name} ===")
    print("hex :", b.hex(" "))
    code0, code1, text_off, img_size, flags = struct.unpack_from("<IIQQQ", b, 0)
    magic = b[32:36]
    print(f"  code0      = 0x{code0:08X}")
    print(f"  code1      = 0x{code1:08X}")
    print(f"  text_offset= 0x{text_off:X}")
    print(f"  image_size = 0x{img_size:X}")
    print(f"  flags      = 0x{flags:X}")
    print(f"  magic      = {magic!r}")
    print()
