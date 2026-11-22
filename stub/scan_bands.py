#!/usr/bin/env python3
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
print('size', w, h)
for gy in range(20):
    y = int(h * (0.30 + 0.40 * gy / 19))
    row = []
    for gx in range(16):
        x = int(w * (0.15 + 0.70 * gx / 15))
        row.append('%02x%02x%02x' % im.getpixel((x, y)))
    print('%4d' % y, ' '.join(row))
