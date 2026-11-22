/*
 * fb_probe2.S — sonda definitiva de framebuffer.
 *
 * Region A (0x9E000000): mitad IZQUIERDA roja, mitad DERECHA verde.
 * Region B (0xFD380000): mitad SUPERIOR azul, mitad INFERIOR amarilla.
 *
 * La orientacion de la division identifica la direccion activa:
 *   division vertical   -> 0x9E000000
 *   division horizontal -> 0xFD380000
 * Si solo se ve un color, las dos regiones son alias o el formato no es 24bpp.
 *
 * Se detiene al final para congelar la imagen.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

_start:
    /* ===== Region A: 0x9E000000, 720 filas de 1600 pix ===== */
    ldr     x19, =0x9E000000
    mov     x20, #720
    movz    x21, #0x12C0                    /* 1600*3 = 4800 */
1:
    mov     x2, x19
    mov     x3, #800                        /* mitad izquierda: rojo */
    mov     w4, #0xFF
    mov     w5, #0x00
    mov     w6, #0x00
    bl      fill
    mov     x3, #800                        /* mitad derecha: verde */
    mov     w4, #0x00
    mov     w5, #0xFF
    mov     w6, #0x00
    bl      fill
    add     x19, x19, x21                   /* 1600 * 3 bytes */
    subs    x20, x20, #1
    b.ne    1b

    /* ===== Region B: 0xFD380000, 2 bloques de 360 filas ===== */
    ldr     x19, =0xFD380000
    movz    x3, #0xCA00                     /* 1600*360 = 0x8CA00 */
    movk    x3, #0x8, lsl #16
    mov     w4, #0x00                       /* superior: azul */
    mov     w5, #0x00
    mov     w6, #0xFF
    bl      fill
    movz    x3, #0xCA00                     /* inferior: amarillo */
    movk    x3, #0x8, lsl #16
    mov     w4, #0xFF
    mov     w5, #0xFF
    mov     w6, #0x00
    bl      fill

hang:
    wfe
    b       hang

/* fill: x2 = destino, x3 = nº pixeles, w4/w5/w6 = RGB */
    .type fill, %function
fill:
2:
    strb    w4, [x2], #1
    strb    w5, [x2], #1
    strb    w6, [x2], #1
    subs    x3, x3, #1
    b.ne    2b
    ret
    .size fill, .-fill

    .ltorg
    .size _start, .-_start
