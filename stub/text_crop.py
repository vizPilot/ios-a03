#!/usr/bin/env python3
"""Recorta la pantalla y mapea el texto blanco puro con alta resolucion."""
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
print('size', w, h)

# region de pantalla segun el grid de colores (cols 3..6, filas 3..8 de 8x12)
X0, X1 = 1400, 3600
Y0, Y1 = 700, 2300

def is_white(r, g, b):
    return r > 200 and g > 200 and b > 200 and max(r,g,b)-min(r,g,b) < 30

pts = []
for y in range(Y0, Y1):
    for x in range(X0, X1):
        if is_white(*im.getpixel((x, y))):
            pts.append((x, y))
if not pts:
    print('sin blancos en el recorte')
    sys.exit(0)
xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
print('texto x=%d..%d y=%d..%d n=%d' % (min(xs), max(xs), min(ys), max(ys), len(pts)))

GW, GH = 100, 45
TX0, TX1, TY0, TY1 = min(xs), max(xs), min(ys), max(ys)
grid = [[0]*GW for _ in range(GH)]
for x, y in pts:
    gx = min(int((x-TX0)*GW/max(1,TX1-TX0+1)), GW-1)
    gy = min(int((y-TY0)*GH/max(1,TY1-TY0+1)), GH-1)
    grid[gy][gx] += 1
for gy in range(GH):
    print('%2d %s' % (gy, ''.join('#' if grid[gy][gx] else '.' for gx in range(GW))))
