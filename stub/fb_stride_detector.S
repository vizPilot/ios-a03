/*
 * fb_stride_detector.S — revela el stride real del framebuffer.
 *
 * Escribe SECUENCIALMENTE desde 0x9E000000 (metodo probado en fb_probe32),
 * con bandas delgadas de colores. Cada banda = 6400 bytes = 1600 pixeles * 4
 * = una fila completa si el stride es realmente 1600 pixeles.
 *
 * Patron (repetido 20 veces = 20 filas):
 *   fila 0: rojo
 *   fila 1: verde
 *   fila 2: azul
 *   fila 3: amarillo
 *   fila 4: blanco
 *   fila 5: negro
 *
 * Si el stride es 1600, veras 20 franjas horizontales de colores pareados.
 * Si el stride es distinto, las franjas saldran diagonales / inclinadas.
 *
 * Solo llena 6*20 = 120 filas = 120*6400 = 768000 bytes (parte alta).
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ FB_LOGO, 0x9E000000
    .equ ROW_BYTES, 6400                    /* 1600 * 4 */
    .equ ROWS, 120

    .macro PIXEL r, g, b
    .byte \b, \g, \r, 0xFF
    .endm

_start:
    /* borrar todo el buffer a negro opaco */
    ldr     x2, =FB_LOGO
    movz    x3, #0x9400
    movk    x3, #0x11, lsl #16              /* 1152000 pixeles */
    mov     w4, #0xFF
    lsl     w4, w4, #24
1:
    str     w4, [x2], #4
    subs    x3, x3, #1
    b.ne    1b

    /* escribir patron de 6 filas repetido 20 veces, secuencial */
    ldr     x2, =FB_LOGO
    mov     x19, #20                        /* repeticiones */
2:
    /* fila roja: 1600 pixeles */
    movz    x3, #0x400
    ldr     x4, =0xFF0000FF                 /* BGRA: B=FF G=00 R=00 A=FF?? */
    /* mejor usar bytes directos: rojo = 00 00 FF FF en little-endian */
    mov     w5, #0xFF
    lsl     w5, w5, #16                     /* 0x00FF0000 -> B=0,G=0,R=FF? no */
    /* usamos word 0xFF0000FF -> bytes FF 00 00 FF = B=FF,G=0,R=0,A=FF (azul) */
    /* para rojo puro: word = 0x0000FFFF -> bytes FF FF 00 00 -> B=FF,G=FF,R=0,A=0 (mal) */
    /* correcto: word 0xFF0000FF? no. Vamos con valores explicitos por byte */
3:
    strb    wzr, [x2], #1                   /* B = 0 */
    strb    wzr, [x2], #1                   /* G = 0 */
    mov     w6, #0xFF
    strb    w6, [x2], #1                    /* R = FF */
    strb    w6, [x2], #1                    /* A = FF */
    subs    x3, x3, #1
    b.ne    3b
    /* fila verde */
    movz    x3, #0x400
4:
    strb    wzr, [x2], #1
    mov     w6, #0xFF
    strb    w6, [x2], #1
    strb    wzr, [x2], #1
    strb    w6, [x2], #1
    subs    x3, x3, #1
    b.ne    4b
    /* fila azul */
    movz    x3, #0x400
5:
    mov     w6, #0xFF
    strb    w6, [x2], #1
    strb    wzr, [x2], #1
    strb    wzr, [x2], #1
    strb    w6, [x2], #1
    subs    x3, x3, #1
    b.ne    5b
    /* fila amarilla */
    movz    x3, #0x400
6:
    strb    wzr, [x2], #1
    mov     w6, #0xFF
    strb    w6, [x2], #1
    strb    w6, [x2], #1
    strb    w6, [x2], #1
    subs    x3, x3, #1
    b.ne    6b
    /* fila blanca */
    movz    x3, #0x400
    mov     w6, #0xFF
7:
    strb    w6, [x2], #1
    strb    w6, [x2], #1
    strb    w6, [x2], #1
    strb    w6, [x2], #1
    subs    x3, x3, #1
    b.ne    7b
    /* fila negra */
    movz    x3, #0x400
8:
    strb    wzr, [x2], #1
    strb    wzr, [x2], #1
    strb    wzr, [x2], #1
    mov     w6, #0xFF
    strb    w6, [x2], #1
    subs    x3, x3, #1
    b.ne    8b

    subs    x19, x19, #1
    b.ne    2b

    /* limpiar cache */
    movz    x21, #0x1880
    movk    x21, #0x1, lsl #16
    ldr     x22, =FB_LOGO
9:
    dc      cvac, x22
    add     x22, x22, #64
    subs    x21, x21, #1
    b.ne    9b
    dsb     sy

10:
    wfe
    b       10b

    .ltorg
    .size _start, .-_start
