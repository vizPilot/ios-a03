#!/usr/bin/env python3
"""Muestrea una foto del framebuffer en rejilla para deducir colores."""
import sys
from PIL import Image
from collections import Counter

path = sys.argv[1]
im = Image.open(path).convert('RGB')
w, h = im.size
print('size:', w, h)

print('grid 8x12:')
for gy in range(12):
    row = []
    for gx in range(8):
        px = im.getpixel((int(w * (gx + 0.5) / 8), int(h * (gy + 0.5) / 12)))
        row.append('%02x%02x%02x' % px)
    print('%2d' % gy, ' '.join(row))

print('dominant:')
for color, n in Counter(im.getdata()).most_common(12):
    print('%02x%02x%02x' % color, n)
