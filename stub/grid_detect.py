#!/usr/bin/env python3
"""Detecta los cuadrados de color de la sonda de rejilla."""
from PIL import Image

im = Image.open('/mnt/d/a03-apple/20261122_154949.jpg').convert('RGB')
w, h = im.size
print('size', w, h)

# Buscar pixeles rojos/verdes/azules/amarillos puros (R,G,B altos, otro bajo)
colors = {
    'R': lambda r,g,b: r > 120 and g < 90 and b < 90,
    'G': lambda r,g,b: g > 120 and r < 90 and b < 90,
    'B': lambda r,g,b: b > 120 and r < 90 and g < 90,
    'Y': lambda r,g,b: r > 120 and g > 120 and b < 90,
}
# busca en toda la imagen, cuenta y min/max de coords
for name, f in colors.items():
    xs, ys = [], []
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            r,g,b = im.getpixel((x,y))
            if f(r,g,b):
                xs.append(x); ys.append(y)
    if xs:
        print(name, 'n=%d'%len(xs), 'x=%d..%d'%(min(xs),max(xs)), 'y=%d..%d'%(min(ys),max(ys)))
    else:
        print(name, 'none')
