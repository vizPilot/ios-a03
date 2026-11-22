/*
 * fb_probe32.S — sonda con pixel ARGB8888 de 32 bits (alfa = 0xFF).
 *
 * Hipotesis: el DPU usa 32bpp. Nuestros intentos anteriores escribieron 3
 * bytes por pixel, dejando el 4º byte (alfa) en 0 -> transparente -> se ve
 * el fondo. Solo la banda blanca (FF FF FF FF) era opaca.
 *
 * 1600x720x4 = 4608000 bytes. Stride = 6400.
 * Bandas horizontales de 180 filas: rojo / verde / azul / blanco.
 *
 * Orden de bytes little-endian para ARGB8888 (0xAARRGGBB):
 *   rojo   = 00 00 FF FF
 *   verde  = 00 FF 00 FF
 *   azul   = FF 00 00 FF
 *   blanco = FF FF FF FF
 *
 * Se detiene al final para congelar la imagen.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ BAND_PIX, 288000                   /* 1600*180 */
    .equ LINES,    72000                    /* 4608000/64 */

    .macro BAND32 r, g, b
    mov     x2, x19
    movz    x3, #0x6500
    movk    x3, #0x4, lsl #16               /* 288000 pixeles */
    mov     w4, #\r
    mov     w5, #\g
    mov     w6, #\b
    bl      fill32
    .endm

_start:
    ldr     x19, =0x9E000000
    BAND32  0x00, 0x00, 0xFF                /* rojo (BGRA: 00 00 FF FF) */
    BAND32  0x00, 0xFF, 0x00                /* verde */
    BAND32  0xFF, 0x00, 0x00                /* azul */
    BAND32  0xFF, 0xFF, 0xFF                /* blanco */

    /* limpiar cache sobre los 4.6 MB escritos */
    movz    x21, #0x1880                    /* 72000 = 0x11880 */
    movk    x21, #0x1, lsl #16
    ldr     x22, =0x9E000000
1:
    dc      cvac, x22
    add     x22, x22, #64
    subs    x21, x21, #1
    b.ne    1b
    dsb     sy

hang:
    wfe
    b       hang

/* fill32: x2 = destino, x3 = nº pixeles, w4/w5/w6 = B,G,R (A=FF) */
    .type fill32, %function
fill32:
2:
    strb    w4, [x2], #1
    strb    w5, [x2], #1
    strb    w6, [x2], #1
    mov     w7, #0xFF
    strb    w7, [x2], #1
    subs    x3, x3, #1
    b.ne    2b
    ret
    .size fill32, .-fill32

    .ltorg
    .size _start, .-_start
