from pathlib import Path
p = Path("/mnt/d/a03/boot.img").read_bytes()
magic = b"SEANDROIDENFORCE"
i = p.find(magic)
print("magic offset:", hex(i), "size after:", len(p) - i)
print("bytes after magic:", p[i + len(magic):i + len(magic) + 32].hex())
j = i + len(magic)
while j < len(p) and p[j] == 0:
    j += 1
print("first nonzero after magic:", hex(j), p[j:j + 16].hex() if j < len(p) else "EOF")
