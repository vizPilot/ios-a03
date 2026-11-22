/*
 * fb_bars.S — diagnostico de geometria: 3 barras horizontales.
 *
 * Fondo negro opaco. Barras blancas:
 *   barra A: y=50..80   (30 px de alto)
 *   barra B: y=150..180 (30 px de alto)
 *   barra C: y=250..280 (30 px de alto)
 * Cada barra va de x=50 a x=550 (500 px de ancho).
 *
 * Si las 3 barras aparecen a igual distancia → la geometria (stride,
 * pixeles de 4 bytes) es correcta y el problema esta en la fuente.
 * Si se ven aplastadas o superpuestas → hay un bug en el calculo de Y.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ FB_LOGO, 0x9E000000
    .equ STRIDE,  1600                      /* pixeles por fila */

_start:
    /* fondo negro opaco: 0xFF000000 por pixel */
    ldr     x2, =FB_LOGO
    movz    x3, #0x9400
    movk    x3, #0x11, lsl #16              /* 1152000 pixeles */
    mov     w4, #0xFF
    lsl     w4, w4, #24
1:
    str     w4, [x2], #4
    subs    x3, x3, #1
    b.ne    1b

    /* barra A: y=50..79 */
    mov     x19, #50
    mov     x20, #80
    mov     w21, #0xFFFFFF                  /* blanco (RGB) */
    bl      draw_bar

    /* barra B: y=150..179 */
    mov     x19, #150
    mov     x20, #180
    bl      draw_bar

    /* barra C: y=250..279 */
    mov     x19, #250
    mov     x20, #280
    bl      draw_bar

    /* limpiar cache */
    movz    x21, #0x1880
    movk    x21, #0x1, lsl #16
    ldr     x22, =FB_LOGO
2:
    dc      cvac, x22
    add     x22, x22, #64
    subs    x21, x21, #1
    b.ne    2b
    dsb     sy

3:
    wfe
    b       3b

/* draw_bar: x19=y0, x20=y1, w21=color. x=50..549 */
    .type draw_bar, %function
draw_bar:
    str     x30, [sp, #-16]!
    mov     x22, x19                        /* y actual */
4:
    mov     x23, #50                        /* x actual */
5:
    movz    x24, #STRIDE
    mul     x25, x22, x24
    add     x25, x25, x23
    lsl     x25, x25, #2
    ldr     x26, =FB_LOGO
    add     x26, x26, x25
    strb    w21, [x26]                      /* B */
    strb    w21, [x26, #1]                  /* G */
    strb    w21, [x26, #2]                  /* R */
    mov     w27, #0xFF
    strb    w27, [x26, #3]                  /* A */
    add     x23, x23, #1
    cmp     x23, #550
    b.lo    5b
    add     x22, x22, #1
    cmp     x22, x20
    b.lo    4b
    ldr     x30, [sp], #16
    ret
    .size draw_bar, .-draw_bar

    .ltorg
    .size _start, .-_start
