#!/usr/bin/env python3
"""Detecta la orientacion de franjas de color en la foto del detector de stride."""
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
print('size', w, h)

# clasificar pixeles por color dominante
def classify(r, g, b):
    mx, mn = max(r,g,b), min(r,g,b)
    if mx < 55:
        return 'K'                          # negro
    if mx - mn < 30:
        return 'W' if mx > 150 else 'w'     # blanco/gris
    if r > 110 and g > 110 and b < 90:
        return 'Y'                          # amarillo
    if r > 110 and g < 90 and b < 90:
        return 'R'                          # rojo
    if g > 110 and r < 90 and b < 90:
        return 'G'                          # verde
    if b > 110 and r < 90 and g < 90:
        return 'B'                          # azul
    return '.'

# conteo global
counts = {}
for y in range(0, h, 4):
    for x in range(0, w, 4):
        c = classify(*im.getpixel((x, y)))
        counts[c] = counts.get(c, 0) + 1
print('conteo:', ' '.join('%s=%d' % (k, counts[k]) for k in sorted(counts)))

# mapa 40x24 para ver orientacion
print('mapa:')
for gy in range(24):
    row = ''
    for gx in range(40):
        x = int(w*(gx+0.5)/40)
        y = int(h*(gy+0.5)/24)
        row += classify(*im.getpixel((x, y)))
    print('%2d %s' % (gy, row))
