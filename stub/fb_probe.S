/*
 * fb_probe.S — sonda de framebuffer: pincha DOS direcciones a la vez.
 *
 * En 0x9E000000 (lcd_base del cmdline): rojo / verde / azul / blanco
 * En 0xFD380000 (fb_reserved del DTB):  negro / amarillo / cian / magenta
 *
 * 4 bandas de 180 filas (1600x180 pixeles, 24bpp) por region.
 * Al final se detiene para que la pantalla quede congelada.
 *
 * Si ves rojo/verde/azul/blanco -> el activo es 0x9E000000.
 * Si ves negro/amarillo/cian/magenta -> el activo es 0xFD380000.
 * El orden de colores tambien revela si es RGB o BGR.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ BAND_PIX, 288000              /* 1600 * 180 = 0x46500 */

    .macro BAND r, g, b
    mov     x2, x19
    movz    x3, #0x6500
    movk    x3, #0x4, lsl #16
    mov     w4, #\r
    mov     w5, #\g
    mov     w6, #\b
    bl      fill_band
    .endm

_start:
    /* ---- region A: lcd_base del logo ---- */
    ldr     x19, =0x9E000000
    BAND    0xFF, 0x00, 0x00           /* rojo (o azul si BGR) */
    BAND    0x00, 0xFF, 0x00           /* verde */
    BAND    0x00, 0x00, 0xFF           /* azul (o rojo si BGR) */
    BAND    0xFF, 0xFF, 0xFF           /* blanco */

    /* ---- region B: framebuffer reservado ---- */
    ldr     x19, =0xFD380000
    BAND    0x00, 0x00, 0x00           /* negro */
    BAND    0xFF, 0xFF, 0x00           /* amarillo */
    BAND    0x00, 0xFF, 0xFF           /* cian */
    BAND    0xFF, 0x00, 0xFF           /* magenta */

hang:
    wfe
    b       hang

/* ------------------------------------------------------------------ */
/* fill_band: x2 = destino, x3 = nº pixeles, w4/w5/w6 = bytes RGB       */
/* ------------------------------------------------------------------ */
    .type fill_band, %function
fill_band:
1:
    strb    w4, [x2], #1
    strb    w5, [x2], #1
    strb    w6, [x2], #1
    subs    x3, x3, #1
    b.ne    1b
    ret
    .size fill_band, .-fill_band

    .ltorg

    .size _start, .-_start
