/*
 * fb_grid.S — sonda de geometria del framebuffer (esquinas + rejilla).
 *
 * Fondo negro opaco. 4 cuadrados de 100x100 en las esquinas:
 *   (100,100)    rojo
 *   (1400,100)   verde
 *   (100,520)    azul
 *   (1400,520)   amarillo
 * Mas rejilla cada 200 px (roja vertical, verde horizontal).
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ FB_LOGO,   0x9E000000
    .equ STRIDE,    1600

_start:
    /* fondo negro opaco */
    ldr     x2, =FB_LOGO
    movz    x3, #0x9400
    movk    x3, #0x11, lsl #16
    mov     w4, #0xFF
    lsl     w4, w4, #24
1:
    str     w4, [x2], #4
    subs    x3, x3, #1
    b.ne    1b

    /* 4 cuadrados: x0=sx, x1=sy, w2=color */
    mov     x0, #100
    mov     x1, #100
    mov     w2, #1
    bl      rect
    mov     x0, #1400
    mov     x1, #100
    mov     w2, #2
    bl      rect
    mov     x0, #100
    mov     x1, #520
    mov     w2, #3
    bl      rect
    mov     x0, #1400
    mov     x1, #520
    mov     w2, #4
    bl      rect

    /* rejilla vertical roja cada 200 px */
    mov     x19, #0
2:
    mov     x20, #0                         /* y */
3:
    mov     x0, x19
    mov     x1, x20
    mov     w2, #1
    bl      px
    add     x20, x20, #1
    cmp     x20, #720
    b.lo    3b
    add     x19, x19, #200
    cmp     x19, #1600
    b.lo    2b

    /* rejilla horizontal verde cada 200 px */
    mov     x19, #0
4:
    mov     x20, #0                         /* x */
5:
    mov     x0, x20
    mov     x1, x19
    mov     w2, #2
    bl      px
    add     x20, x20, #1
    cmp     x20, #1600
    b.lo    5b
    add     x19, x19, #200
    cmp     x19, #720
    b.lo    4b

    /* limpiar cache */
    movz    x21, #0x1880
    movk    x21, #0x1, lsl #16
    ldr     x22, =FB_LOGO
6:
    dc      cvac, x22
    add     x22, x22, #64
    subs    x21, x21, #1
    b.ne    6b
    dsb     sy

hang:
    wfe
    b       hang

/* rect: x0=sx, x1=sy, w2=color. Usa x5..x9 como temporales */
    .type rect, %function
rect:
    str     x30, [sp, #-16]!                /* salvar lr: px lo sobrescribe */
    mov     x5, x0                          /* x5 = sx (guardado) */
    mov     x6, x1                          /* x6 = sy (fila actual) */
    mov     x7, #100                        /* filas restantes */
10:
    mov     x8, x5                          /* x8 = x actual */
    mov     x9, #100                        /* columnas restantes */
11:
    mov     x0, x8
    mov     x1, x6
    bl      px
    add     x8, x8, #1
    subs    x9, x9, #1
    b.ne    11b
    add     x6, x6, #1
    subs    x7, x7, #1
    b.ne    10b
    ldr     x30, [sp], #16                  /* restaurar lr */
    ret
    .size rect, .-rect

/* px: x0=x, x1=y, w2=color (1=R 2=G 3=B 4=Y). Usa x10..x13, w4..w6,w12 */
    .type px, %function
px:
    movz    x10, #STRIDE
    mul     x11, x1, x10
    add     x11, x11, x0
    lsl     x11, x11, #2
    ldr     x13, =FB_LOGO
    add     x13, x13, x11
    cmp     w2, #1
    b.eq    20f
    cmp     w2, #2
    b.eq    21f
    cmp     w2, #3
    b.eq    22f
    mov     w4, #0x00                       /* amarillo */
    mov     w5, #0xFF
    mov     w6, #0xFF
    b       23f
20:
    mov     w4, #0x00                       /* rojo */
    mov     w5, #0x00
    mov     w6, #0xFF
    b       23f
21:
    mov     w4, #0x00                       /* verde */
    mov     w5, #0xFF
    mov     w6, #0x00
    b       23f
22:
    mov     w4, #0xFF                       /* azul */
    mov     w5, #0x00
    mov     w6, #0x00
23:
    strb    w4, [x13]
    strb    w5, [x13, #1]
    strb    w6, [x13, #2]
    mov     w12, #0xFF
    strb    w12, [x13, #3]
    ret
    .size px, .-px

    .ltorg
    .size _start, .-_start
