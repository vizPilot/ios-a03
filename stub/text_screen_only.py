#!/usr/bin/env python3
"""Aísla la pantalla (region oscura) y dibuja mapa de texto claro."""
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
print('size', w, h)

# segun analyze_photo grid 8x12: pantalla oscura en cols 4..7, filas 4..9
X0, X1 = int(w*0.50), int(w*0.99)
Y0, Y1 = int(h*0.32), int(h*0.82)

def bright(r, g, b):
    return (r+g+b)//3 > 120 and max(r,g,b)-min(r,g,b) < 60

pts = []
for y in range(Y0, Y1):
    for x in range(X0, X1):
        if bright(*im.getpixel((x, y))):
            pts.append((x, y))
print('recorte x=%d..%d y=%d..%d  n=%d' % (X0, X1, Y0, Y1, len(pts)))
if not pts:
    sys.exit(0)
xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
print('claros x=%d..%d y=%d..%d' % (min(xs), max(xs), min(ys), max(ys)))

GW, GH = 90, 35
TX0, TX1, TY0, TY1 = min(xs), max(xs), min(ys), max(ys)
grid = [[0]*GW for _ in range(GH)]
for x, y in pts:
    gx = min(int((x-TX0)*GW/max(1,TX1-TX0+1)), GW-1)
    gy = min(int((y-TY0)*GH/max(1,TY1-TY0+1)), GH-1)
    grid[gy][gx] += 1
for gy in range(GH):
    print('%2d %s' % (gy, ''.join('#' if grid[gy][gx]>=3 else ('+' if grid[gy][gx] else '.') for gx in range(GW))))
