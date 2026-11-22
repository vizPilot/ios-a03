#!/usr/bin/env python3
"""Compara cuadrantes de la pantalla para detectar divisiones de color."""
import sys
from PIL import Image, ImageStat

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
# region central de la pantalla (estimada del grid 8x12)
x0, x1 = int(w*0.20), int(w*0.80)
y0, y1 = int(h*0.25), int(h*0.75)
print('screen crop:', x0, y0, x1, y1)

def mean(box):
    return tuple(round(v, 1) for v in ImageStat.Stat(im.crop(box)).mean)

mx = (x0+x1)//2
my = (y0+y1)//2
print('TOP    :', mean((x0, y0, x1, my)))
print('BOTTOM :', mean((x0, my, x1, y1)))
print('LEFT   :', mean((x0, y0, mx, y1)))
print('RIGHT  :', mean((mx, y0, x1, y1)))
print('TL:', mean((x0, y0, mx, my)))
print('TR:', mean((mx, y0, x1, my)))
print('BL:', mean((x0, my, mx, y1)))
print('BR:', mean((mx, my, x1, y1)))
