#!/usr/bin/env python3
"""Mapea texto claro sobre fondo oscuro usando contraste local."""
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
X0, X1 = 1200, 3700
Y0, Y1 = 600, 2400

# umbral relativo: pixel mucho mas claro que el fondo
def bright(r, g, b):
    v = (r+g+b)//3
    return v > 110 and max(r,g,b)-min(r,g,b) < 70

pts = []
for y in range(Y0, Y1, 2):
    for x in range(X0, X1, 2):
        if bright(*im.getpixel((x, y))):
            pts.append((x, y))
print('n=%d' % len(pts))
if not pts:
    sys.exit(0)
xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
print('x=%d..%d y=%d..%d' % (min(xs), max(xs), min(ys), max(ys)))

GW, GH = 110, 50
TX0, TX1, TY0, TY1 = min(xs), max(xs), min(ys), max(ys)
grid = [[0]*GW for _ in range(GH)]
for x, y in pts:
    gx = min(int((x-TX0)*GW/max(1,TX1-TX0+1)), GW-1)
    gy = min(int((y-TY0)*GH/max(1,TY1-TY0+1)), GH-1)
    grid[gy][gx] += 1
for gy in range(GH):
    row = ''.join('#' if grid[gy][gx]>=2 else ('+' if grid[gy][gx] else '.') for gx in range(GW))
    print('%2d %s' % (gy, row))
