#!/usr/bin/env python3
"""Analiza la forma del texto blanco sobre negro en la foto."""
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
print('size', w, h)

# Detectar pixeles de texto blanco (todos los canales altos y parejos)
def is_white(r, g, b):
    return r > 180 and g > 180 and b > 180 and max(r,g,b)-min(r,g,b) < 40

pts = []
for y in range(h):
    for x in range(w):
        if is_white(*im.getpixel((x, y))):
            pts.append((x, y))

if not pts:
    print('sin pixeles blancos')
    sys.exit(0)

xs = [p[0] for p in pts]
ys = [p[1] for p in pts]
print('blancos=%d  x=%d..%d  y=%d..%d' % (len(pts), min(xs), max(xs), min(ys), max(ys)))

# Mapa ASCII 100x60 del area de texto, 1 = blanco
X0, X1, Y0, Y1 = min(xs), max(xs), min(ys), max(ys)
GW, GH = 100, 60
grid = [[0]*GW for _ in range(GH)]
for x, y in pts:
    gx = int((x - X0) * GW / max(1, X1 - X0 + 1))
    gy = int((y - Y0) * GH / max(1, Y1 - Y0 + 1))
    gx = min(gx, GW-1); gy = min(gy, GH-1)
    grid[gy][gx] += 1

print('mapa (cada celda = blanco presente):')
for gy in range(GH):
    row = ''.join('#' if grid[gy][gx] else '.' for gx in range(GW))
    print('%2d %s' % (gy, row))
