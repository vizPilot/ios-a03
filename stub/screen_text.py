#!/usr/bin/env python3
"""Aísla la pantalla oscura y mapea el texto blanco dentro de ella."""
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
print('size', w, h)

# 1) bounding box de pixeles muy oscuros (fondo del framebuffer)
dark = []
for y in range(0, h, 3):
    for x in range(0, w, 3):
        r, g, b = im.getpixel((x, y))
        if max(r, g, b) < 45:
            dark.append((x, y))
if not dark:
    print('sin region oscura')
    sys.exit(0)
xs = [p[0] for p in dark]; ys = [p[1] for p in dark]
X0, X1, Y0, Y1 = min(xs), max(xs), min(ys), max(ys)
print('pantalla aprox x=%d..%d y=%d..%d' % (X0, X1, Y0, Y1))

# 2) dentro de la pantalla, pixeles de texto blanco
def is_white(r, g, b):
    return r > 170 and g > 170 and b > 170 and max(r,g,b)-min(r,g,b) < 45

pts = []
for y in range(Y0, Y1+1):
    for x in range(X0, X1+1):
        if is_white(*im.getpixel((x, y))):
            pts.append((x, y))
if not pts:
    print('sin texto blanco dentro de la pantalla')
    sys.exit(0)
xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
print('texto x=%d..%d y=%d..%d  n=%d' % (min(xs), max(xs), min(ys), max(ys), len(pts)))

# 3) mapa ASCII 120x40 del texto
TX0, TX1, TY0, TY1 = min(xs), max(xs), min(ys), max(ys)
GW, GH = 120, 40
grid = [[0]*GW for _ in range(GH)]
for x, y in pts:
    gx = min(int((x-TX0)*GW/max(1,TX1-TX0+1)), GW-1)
    gy = min(int((y-TY0)*GH/max(1,TY1-TY0+1)), GH-1)
    grid[gy][gx] += 1
print('mapa del texto:')
for gy in range(GH):
    print('%2d %s' % (gy, ''.join('#' if grid[gy][gx] else '.' for gx in range(GW))))
