#!/usr/bin/env python3
"""Mapa de colores de la foto de la rejilla, 40x24 celdas."""
from PIL import Image

im = Image.open('/mnt/d/a03-apple/20261122_154949.jpg').convert('RGB')
w, h = im.size

def classify(r, g, b):
    mx, mn = max(r,g,b), min(r,g,b)
    if mx < 60:
        return '.'                          # negro
    if mx - mn < 35:
        return ':' if mx < 130 else '#'     # gris
    if r > g and r > b:
        return 'R' if r > 130 else 'r'
    if g > r and g > b:
        return 'G' if g > 130 else 'g'
    if b > r and b > g:
        return 'B' if b > 130 else 'b'
    return '?'

for gy in range(24):
    row = ''
    for gx in range(40):
        x = int(w*(gx+0.5)/40)
        y = int(h*(gy+0.5)/24)
        row += classify(*im.getpixel((x,y)))
    print('%2d %s' % (gy, row))
