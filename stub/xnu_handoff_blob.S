/*
 * xnu_handoff_blob.S — valida el handoff estilo _start, barra por campo.
 *
 * Entrada: x0 = &boot_args (0x92000000), MMU off, sin stack.
 *
 * Dibuja 7 barras de 16 filas cada una a partir de y=200. Verde = check OK,
 * rojo = check fallido. Orden de arriba abajo:
 *
 *   y=200  x0 == 0x92000000
 *   y=216  Revision == 2
 *   y=232  Version == 2
 *   y=248  deviceTreeP apunta a FDT magic 0xEDFE0DD0 (leido en LE)
 *   y=264  deviceTreeLength == 376049
 *   y=280  CommandLine[0] == 'd'
 *   y=296  physBase == 0x80000000
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ FB_LOGO, 0x9E000000
    .equ ROW_PX,  720
    .equ ROW_BYTES, 2880
    .equ BAR_ROWS, 16
    .equ Y0, 200

_start:
    mov     x19, x0                         /* x19 = &boot_args */
    mov     x20, #0                         /* bitmask: bit i = check i OK */

    /* check 0: x0 */
    movz    x9, #0
    movk    x9, #0x9200, lsl #16            /* 0x92000000 */
    cmp     x19, x9
    b.ne    chk0_done
    orr     x20, x20, #1
chk0_done:
    /* check 1: Revision */
    ldrh    w1, [x19, #0]
    cmp     w1, #2
    b.ne    chk1_done
    orr     x20, x20, #2
chk1_done:
    /* check 2: Version */
    ldrh    w1, [x19, #2]
    cmp     w1, #2
    b.ne    chk2_done
    orr     x20, x20, #4
chk2_done:
    /* check 3: FDT magic */
    ldr     x2, [x19, #96]
    ldr     w3, [x2]
    ldr     w4, =0xEDFE0DD0
    cmp     w3, w4
    b.ne    chk3_done
    orr     x20, x20, #8
chk3_done:
    /* check 4: deviceTreeLength */
    ldr     w5, [x19, #104]
    ldr     w6, =376049
    cmp     w5, w6
    b.ne    chk4_done
    orr     x20, x20, #16
chk4_done:
    /* check 5: CommandLine[0] */
    ldrb    w7, [x19, #108]
    cmp     w7, #'d'
    b.ne    chk5_done
    orr     x20, x20, #32
chk5_done:
    /* check 6: physBase  (CORREGIDO: lsl #16, no #32) */
    ldr     x8, [x19, #16]
    movz    x9, #0
    movk    x9, #0x8000, lsl #16            /* 0x80000000 */
    cmp     x8, x9
    b.ne    chk6_done
    orr     x20, x20, #64
chk6_done:
    /* ---------- dibujar 7 barras ---------- */
    mov     x21, #0                         /* indice de barra */
draw_loop:
    cmp     x21, #7
    b.eq    draw_done

    mov     x22, #Y0
    mov     x23, #BAR_ROWS
    mul     x24, x21, x23
    add     x22, x22, x24                   /* y de esta barra */
    movz    x25, #(ROW_BYTES & 0xffff)
    movk    x25, #((ROW_BYTES >> 16) & 0xffff), lsl #16
    mul     x26, x22, x25                   /* offset en bytes */
    ldr     x8, =FB_LOGO
    add     x8, x8, x26

    lsr     x27, x20, x21
    and     x27, x27, #1
    cmp     x27, #1
    b.eq    color_green
    ldr     w10, =0xFFFF0000                /* rojo = fallo */
    b       color_ready
color_green:
    ldr     w10, =0xFF00FF00                /* verde = OK */
color_ready:
    mov     x7, #(BAR_ROWS * ROW_PX)        /* 11520 pixeles */
pixel_loop:
    str     w10, [x8], #4
    subs    x7, x7, #1
    b.ne    pixel_loop

    /* coherencia: 11520*4 = 46080 bytes = 720 lineas */
    movz    x28, #(BAR_ROWS * ROW_BYTES)    /* 46080 = 0xB400 */
    sub     x8, x8, x28
    mov     x9, #720
cache_loop:
    dc      cvac, x8
    add     x8, x8, #64
    subs    x9, x9, #1
    b.ne    cache_loop
    dsb     sy

    add     x21, x21, #1
    b       draw_loop
draw_done:
    isb     sy
freeze:
    wfe
    b       freeze

    .ltorg
    .size _start, .-_start
