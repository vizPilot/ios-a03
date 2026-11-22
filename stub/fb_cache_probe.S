/*
 * fb_cache_probe.S — sonda con LIMPIEZA DE CACHE de datos.
 *
 * El payload corre con la MMU/cache heredadas de LK. Los strb pueden quedar
 * en L1/L2 y no llegar a DRAM; el DPU lee por DMA y ve la imagen vieja.
 * Este payload limpia la cache (dc cvac) sobre cada region escrita.
 *
 * 0x9E000000: 4 bandas horizontales (rojo/verde/azul/blanco)
 * 0xFD380000: magenta solido
 *
 * Se detiene al final para congelar la imagen.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ BAND_PIX, 288000                   /* 1600*180 */
    .equ FB_PIX,   1152000                  /* 1600*720 */
    .equ LINES,    54000                    /* 3456000/64 */

    .macro BAND r, g, b
    mov     x2, x19
    movz    x3, #0x6500
    movk    x3, #0x4, lsl #16
    mov     w4, #\r
    mov     w5, #\g
    mov     w6, #\b
    bl      fill
    .endm

_start:
    /* ---- 0x9E000000: 4 bandas ---- */
    ldr     x19, =0x9E000000
    BAND    0xFF, 0x00, 0x00
    BAND    0x00, 0xFF, 0x00
    BAND    0x00, 0x00, 0xFF
    BAND    0xFF, 0xFF, 0xFF

    /* ---- 0xFD380000: magenta solido ---- */
    ldr     x19, =0xFD380000
    movz    x3, #0x9400
    movk    x3, #0x11, lsl #16              /* 1152000 */
    mov     w4, #0xFF
    mov     w5, #0x00
    mov     w6, #0xFF
    bl      fill

    /* ---- limpiar cache de datos sobre ambas regiones ---- */
    mov     x21, #LINES
    ldr     x22, =0x9E000000
    ldr     x23, =0xFD380000
1:
    dc      cvac, x22
    dc      cvac, x23
    add     x22, x22, #64
    add     x23, x23, #64
    subs    x21, x21, #1
    b.ne    1b
    dsb     sy

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
