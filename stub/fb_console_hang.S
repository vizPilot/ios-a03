/*
 * fb_console.S — "UART" por framebuffer para el A03 (CALIBRADO).
 *
 * Configuracion validada:
 *   base     = 0x9E000000  (logobuffer, sprd,logo-memory)
 *   tamaño   = 1600x720, 32bpp ARGB8888, little-endian (BB GG RR AA)
 *   stride   = 6400 bytes
 *   total    = 4608000 bytes (0x464E00)
 *
 * Entra desde code0 con x0 = FDT. No copia nada a RAM: se ejecuta dentro
 * del propio payload (mismo esquema que xnu_entry_probe, que arranco).
 *
 * Hace:
 *   1. construir boot_args en 0x92000000;
 *   2. escribir "FB:<checksum>:D" en linux_proc_banner;
 *   3. borrar el framebuffer y dibujar texto con fuente 5x7 escalada 3x;
 *   4. dc cvac sobre el framebuffer (el DPU lee por DMA);
 *   5. volver a stext con x0 = FDT.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x0169E810
    .equ STOCK_ENTRY, 0x01200000

    .equ BA_DST,      0x92000000
    .equ PROC_OFF,    0x010623A0
    .equ BA_WORDS,    144

    .equ FB_LOGO,     0x9E000000
    .equ FB_W,        1600
    .equ FB_STRIDE,   1600                   /* pixeles por fila (NO bytes) */
    .equ FB_BYTES,    4608000                /* 1600*720*4 = 0x464E00 */
    .equ FB_WORDS,    288000                 /* FB_BYTES / 16 */
    .equ FB_LINES,    72000                  /* FB_BYTES / 64 */

_start:
    mov     x22, x0                         /* conservar FDT */
    adr     x23, _start                     /* PC real del payload */
    movz    x24, #(PAYLOAD_VMA & 0xffff)
    movk    x24, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x24, x23, x24                   /* x24 = image_base */

    /* ---------- 1. boot_args ---------- */
    movz    x19, #(BA_DST & 0xffff)
    movk    x19, #((BA_DST >> 16) & 0xffff), lsl #16

    mov     x5, #BA_WORDS
    mov     x6, x19
2:
    str     xzr, [x6], #8
    subs    x5, x5, #1
    b.ne    2b

    mov     w5, #2
    strh    w5, [x19, #0]
    strh    w5, [x19, #2]

    ldr     x5, =0xfffffff007004000
    str     x5, [x19, #8]
    ldr     x5, =0x0000000080000000
    str     x5, [x19, #16]
    ldr     x5, =0x00000000fffff000
    str     x5, [x19, #24]
    str     x5, [x19, #1144]

    adr     x6, cmdline
    add     x7, x19, #108
3:
    ldrb    w8, [x6], #1
    strb    w8, [x7], #1
    cbnz    w8, 3b

    ldr     w5, [x22]
    ldr     w6, [x22, #4]
    rev     w6, w6
    mov     w20, #'X'
    ldr     w21, =0xEDFE0DD0
    cmp     w5, w21
    b.ne    8f
    mov     w20, #'D'
8:
    str     x22, [x19, #96]
    str     w6, [x19, #104]

    /* checksum de boot_args -> x21 */
    mov     x9, x19
    mov     x10, #BA_WORDS
    mov     x21, #0
4:
    ldr     x12, [x9], #8
    add     x21, x21, x12
    subs    x10, x10, #1
    b.ne    4b
    mov     x27, x21                        /* guardar checksum */

    /* ---------- 2. /proc/version (canal secundario) ---------- */
    movz    x13, #(PROC_OFF & 0xffff)
    movk    x13, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x13, x24, x13

    adr     x14, report_prefix
5:
    ldrb    w15, [x14], #1
    strb    w15, [x13], #1
    cbnz    w15, 5b
    sub     x13, x13, #1

    mov     x28, #16                        /* nibbles (no x16: fb_putc lo usa) */
6:
    sub     x28, x28, #1
    lsl     x18, x28, #2
    lsr     x12, x21, x18
    and     x12, x12, #0xf
    adr     x16, hexchars
    ldrb    w12, [x16, x12]
    strb    w12, [x13], #1
    cbnz    x28, 6b

    strb    w20, [x13], #1                  /* D o X */
    strb    wzr, [x13]

    /* ---------- 3. borrar framebuffer a NEGRO OPACO ---------- */
    /* En ARGB8888, cero = alfa 0 = transparente -> se ve el logo debajo.
       Escribimos 0xFF000000 (little-endian: 00 00 00 FF) en cada pixel. */
    ldr     x2, =FB_LOGO
    movz    x3, #0x9400                     /* 1600*720 = 1152000 = 0x119400 */
    movk    x3, #0x11, lsl #16
    mov     w4, #0xFF
    lsl     w4, w4, #24                     /* 0xFF000000 = B=0,G=0,R=0,A=FF */
7:
    str     w4, [x2], #4
    subs    x3, x3, #1
    b.ne    7b

    /* ---------- 4. dibujar texto ---------- */
    mov     x25, #0                         /* columna (caracteres) */
    mov     x26, #0                         /* fila (caracteres) */

    adr     x0, s_banner
    bl      fb_print_str
    adr     x0, s_ck
    bl      fb_print_str
    mov     x21, x27
    bl      fb_print_hex64
    mov     w0, #'\n'
    bl      fb_putc

    adr     x0, s_pc
    bl      fb_print_str
    mov     x21, x23                        /* PC real */
    bl      fb_print_hex64
    mov     w0, #'\n'
    bl      fb_putc

    adr     x0, s_fdt
    bl      fb_print_str
    mov     w0, w20                         /* D o X */
    bl      fb_putc
    mov     w0, #'\n'
    bl      fb_putc

    adr     x0, s_ret
    bl      fb_print_str

    /* ---------- 5. limpiar cache (DPU lee por DMA) ---------- */
    mov     x20, x22                        /* preservar FDT: x22 se sobrescribe abajo */
    movz    x21, #0x1880                    /* FB_LINES = 72000 = 0x11880 */
    movk    x21, #0x1, lsl #16
    ldr     x22, =FB_LOGO
9:
    dc      cvac, x22
    add     x22, x22, #64
    subs    x21, x21, #1
    b.ne    9b
    dsb     sy

    /* ---------- 6. CONGELAR la imagen ---------- */
hang_console:
    wfe
    b       hang_console

    .ltorg

/* ------------------------------------------------------------------ */
/* fb_pixel: x7 = x, x9 = y, w14 = byte de color                        */
/* ------------------------------------------------------------------ */
    .type fb_pixel, %function
fb_pixel:
    movz    x10, #FB_STRIDE                 /* 1600 pixeles por fila */
    mul     x11, x9, x10
    add     x11, x11, x7
    lsl     x11, x11, #2                    /* * 4 bytes por pixel */
    ldr     x13, =FB_LOGO
    add     x13, x13, x11
    strb    w14, [x13]                      /* B */
    strb    w14, [x13, #1]                  /* G */
    strb    w14, [x13, #2]                  /* R */
    mov     w12, #0xFF
    strb    w12, [x13, #3]                  /* A = opaco */
    ret
    .size fb_pixel, .-fb_pixel

/* ------------------------------------------------------------------ */
/* fb_putc: w0 = caracter. x25 = columna, x26 = fila                    */
/* ------------------------------------------------------------------ */
    .type fb_putc, %function
fb_putc:
    str     x30, [sp, #-16]!                /* salvar lr: fb_pixel lo sobrescribe */
    cmp     w0, #0x0A
    b.eq    20f

    mov     w2, w0
    mov     w3, #'0'
    sub     w2, w2, w3
    cmp     w2, #43
    b.hs    21f
    adr     x3, font_table
    add     x3, x3, x2, lsl #2
    add     x3, x3, x2                      /* x3 = &font[ch*5] */
    b       22f
21:
    adr     x3, font_blank
22:
    mov     x4, #0                          /* fila del glyph 0..6 */
23:
    mov     x5, #0                          /* columna del glyph 0..4 */
24:
    ldrb    w6, [x3, x5]
    lsr     w6, w6, w4
    and     w6, w6, #1

    /* escala 4x: celda de caracter = 6*4 = 24 px ancho, 8*4 = 32 px alto
       (1 columna/fila de separacion para que no se peguen) */
    mov     x7, x25
    mov     x8, #6
    mul     x7, x7, x8
    add     x7, x7, x5
    mov     x8, #4
    mul     x7, x7, x8                      /* x de pantalla */

    mov     x9, x26
    mov     x8, #8
    mul     x9, x9, x8
    add     x9, x9, x4
    mov     x8, #4
    mul     x9, x9, x8                      /* y de pantalla */

    mov     w14, #0
    cmp     w6, #0
    b.eq    25f
    mov     w14, #0xFF
25:
    mov     x15, #4                         /* 4 filas de pantalla */
26:
    mov     x16, #4                         /* 4 columnas de pantalla */
27:
    bl      fb_pixel
    add     x7, x7, #1
    subs    x16, x16, #1
    b.ne    27b
    sub     x7, x7, #4
    add     x9, x9, #1
    subs    x15, x15, #1
    b.ne    26b

    add     x5, x5, #1
    cmp     x5, #5
    b.ne    24b
    add     x4, x4, #1
    cmp     x4, #7
    b.ne    23b

    add     x25, x25, #1
    cmp     x25, #64                        /* 1600/24 = 66 caracteres */
    b.lo    28f
    mov     x25, #0
    add     x26, x26, #1
28:
    ldr     x30, [sp], #16                  /* restaurar lr */
    ret

20:
    mov     x25, #0
    add     x26, x26, #1
    ldr     x30, [sp], #16                  /* restaurar lr */
    ret
    .size fb_putc, .-fb_putc

/* ------------------------------------------------------------------ */
/* fb_print_str: x0 = cadena terminada en 0                            */
/* ------------------------------------------------------------------ */
    .type fb_print_str, %function
fb_print_str:
    str     x30, [sp, #-16]!                /* salvar lr: fb_putc lo sobrescribe */
    mov     x29, x0
29:
    ldrb    w0, [x29], #1
    cbz     w0, 30f
    bl      fb_putc
    b       29b
30:
    ldr     x30, [sp], #16                  /* restaurar lr */
    ret
    .size fb_print_str, .-fb_print_str

/* ------------------------------------------------------------------ */
/* fb_print_hex64: x21 = valor                                         */
/* ------------------------------------------------------------------ */
    .type fb_print_hex64, %function
fb_print_hex64:
    str     x30, [sp, #-16]!                /* salvar lr: fb_putc lo sobrescribe */
    mov     x28, #16                        /* nibbles (no x16) */
31:
    sub     x28, x28, #1
    lsl     x2, x28, #2
    lsr     x2, x21, x2
    and     x2, x2, #0xf
    adr     x17, hexchars
    ldrb    w0, [x17, x2]
    bl      fb_putc
    cbnz    x28, 31b
    ldr     x30, [sp], #16                  /* restaurar lr */
    ret
    .size fb_print_hex64, .-fb_print_hex64

    .ltorg

cmdline:
    .asciz  "debug=0x8 kext-dev-mode=1"
report_prefix:
    .asciz  "FB:"
hexchars:
    .ascii  "0123456789abcdef"

s_banner:
    .asciz  "XNU A03 FB UART\n"
s_ck:
    .asciz  "BA CK "
s_pc:
    .asciz  "PC "
s_fdt:
    .asciz  "FDT "
s_ret:
    .asciz  "RET OK\n"

    .balign 4
font_blank:
    .byte 0,0,0,0,0

/* Fuente 5x7 indexada por ASCII-'0' (0x30..0x5A) */
font_table:
    /* 0 */  .byte 0x3E,0x51,0x49,0x45,0x3E
    /* 1 */  .byte 0x00,0x42,0x7F,0x40,0x00
    /* 2 */  .byte 0x42,0x61,0x51,0x49,0x46
    /* 3 */  .byte 0x21,0x41,0x45,0x4B,0x31
    /* 4 */  .byte 0x18,0x14,0x12,0x7F,0x10
    /* 5 */  .byte 0x27,0x45,0x45,0x45,0x39
    /* 6 */  .byte 0x3C,0x4A,0x49,0x49,0x30
    /* 7 */  .byte 0x01,0x71,0x09,0x05,0x03
    /* 8 */  .byte 0x36,0x49,0x49,0x49,0x36
    /* 9 */  .byte 0x06,0x49,0x49,0x29,0x1E
    /* : */  .byte 0x00,0x36,0x36,0x00,0x00
    /* ;<=>?@ */ .byte 0,0,0,0,0
              .byte 0,0,0,0,0
              .byte 0,0,0,0,0
              .byte 0,0,0,0,0
              .byte 0,0,0,0,0
              .byte 0,0,0,0,0
    /* A */  .byte 0x7E,0x11,0x11,0x11,0x7E
    /* B */  .byte 0x7F,0x49,0x49,0x49,0x36
    /* C */  .byte 0x3E,0x41,0x41,0x41,0x22
    /* D */  .byte 0x7F,0x41,0x41,0x22,0x1C
    /* E */  .byte 0x7F,0x49,0x49,0x49,0x41
    /* F */  .byte 0x7F,0x09,0x09,0x09,0x01
    /* G */  .byte 0x3E,0x41,0x49,0x49,0x7A
    /* H */  .byte 0x7F,0x08,0x08,0x08,0x7F
    /* I */  .byte 0x00,0x41,0x7F,0x41,0x00
    /* J */  .byte 0x20,0x40,0x41,0x3F,0x01
    /* K */  .byte 0x7F,0x08,0x14,0x22,0x41
    /* L */  .byte 0x7F,0x40,0x40,0x40,0x40
    /* M */  .byte 0x7F,0x02,0x0C,0x02,0x7F
    /* N */  .byte 0x7F,0x04,0x08,0x10,0x7F
    /* O */  .byte 0x3E,0x41,0x41,0x41,0x3E
    /* P */  .byte 0x7F,0x09,0x09,0x09,0x06
    /* Q */  .byte 0x3E,0x41,0x51,0x21,0x5E
    /* R */  .byte 0x7F,0x09,0x19,0x29,0x46
    /* S */  .byte 0x46,0x49,0x49,0x49,0x31
    /* T */  .byte 0x01,0x01,0x7F,0x01,0x01
    /* U */  .byte 0x3F,0x40,0x40,0x40,0x3F
    /* V */  .byte 0x1F,0x20,0x40,0x20,0x1F
    /* W */  .byte 0x3F,0x40,0x38,0x40,0x3F
    /* X */  .byte 0x63,0x14,0x08,0x14,0x63
    /* Y */  .byte 0x07,0x08,0x70,0x08,0x07
    /* Z */  .byte 0x61,0x51,0x49,0x45,0x43

    .size _start, .-_start
