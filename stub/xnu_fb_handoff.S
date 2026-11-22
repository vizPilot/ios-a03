/*
 * xnu_fb_handoff.S — CONSOLA FRAMEBUFFER + HANDOFF estilo _start de XNU.
 *
 * Integra los dos canales ya validados por separado:
 *   - fb_console_final.S  (framebuffer 720x1600 legible + /proc/version FB:...:D)
 *   - xnu_entry_probe.S   (handoff x0=&boot_args -> :XNUOK)
 *
 * Configuracion VALIDADA por foto (20261122_161703.jpg):
 *   base     = 0x9E000000
 *   ancho    = 720 pixeles por fila (2880 bytes/fila)  <-- clave
 *   alto     = 1600 filas
 *   total    = 1152000 pixeles = 4608000 bytes
 *   formato  = 32bpp BGRA little-endian (B,G,R,A=0xFF)
 *   metodo   = escritura SECUENCIAL (sin mul para direcciones)
 *   cache    = dc cvac obligatorio (DPU lee por DMA)
 *
 * Nota: el cmdline del DTB dice lcd_size=1600x720, pero eso es la resolucion
 * del panel; el BUFFER en memoria es 720x1600 (vertical).
 *
 * Hace:
 *   1. construir boot_args en 0x92000000;
 *   2. escribir "FB:<checksum>:D" en linux_proc_banner (/proc/version);
 *   3. borrar el framebuffer y dibujar 3 lineas de texto;
 *   4. dc cvac sobre 4.6 MB;
 *   5. handoff: x0=&boot_args, salto a xnu_entry;
 *   6. xnu_entry valida y anade ":XNUOK"/":XNUBAD" a /proc/version;
 *   7. xnu_entry dibuja una franja VERDE (OK) o ROJA (fallo) en y=96..127;
 *   8. volver a stext con x0 = FDT.
 *
 * IMPORTANTE: xnu_entry es una SONDA que simula _start de XNU. Todavia no
 * existe kernelcache propio para T606; esto NO arranca XNU real.
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
    .equ ROW_PX,      720
    .equ TOTAL_PX,    1152000                 /* 720 * 1600 */

_start:
    mov     x22, x0                         /* conservar FDT */
    str     x22, [sp, #-16]!                /* guardar FDT en pila */
    adr     x23, _start                     /* PC real del payload */
    movz    x24, #(PAYLOAD_VMA & 0xffff)
    movk    x24, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x24, x23, x24                   /* x24 = image_base */

    /* ---------- 1. boot_args ---------- */
    movz    x19, #(BA_DST & 0xffff)
    movk    x19, #((BA_DST >> 16) & 0xffff), lsl #16
    mov     x5, #BA_WORDS
    mov     x6, x19
1:
    str     xzr, [x6], #8
    subs    x5, x5, #1
    b.ne    1b

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
2:
    ldrb    w8, [x6], #1
    strb    w8, [x7], #1
    cbnz    w8, 2b

    ldr     w5, [x22]
    ldr     w6, [x22, #4]
    rev     w6, w6
    mov     w20, #'X'
    ldr     w21, =0xEDFE0DD0
    cmp     w5, w21
    b.ne    3f
    mov     w20, #'D'
3:
    str     x22, [x19, #96]
    str     w6, [x19, #104]

    /* checksum de boot_args -> x27 */
    mov     x9, x19
    mov     x10, #BA_WORDS
    mov     x27, #0
4:
    ldr     x12, [x9], #8
    add     x27, x27, x12
    subs    x10, x10, #1
    b.ne    4b

    /* ---------- 2. /proc/version ---------- */
    movz    x13, #(PROC_OFF & 0xffff)
    movk    x13, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x13, x24, x13
    adr     x14, report_prefix
5:
    ldrb    w15, [x14], #1
    strb    w15, [x13], #1
    cbnz    w15, 5b
    sub     x13, x13, #1
    mov     x28, #16
6:
    sub     x28, x28, #1
    lsl     x18, x28, #2
    lsr     x12, x27, x18
    and     x12, x12, #0xf
    adr     x16, hexchars
    ldrb    w12, [x16, x12]
    strb    w12, [x13], #1
    cbnz    x28, 6b
    strb    w20, [x13], #1
    strb    wzr, [x13]

    /* ---------- 3. borrar framebuffer a negro opaco (secuencial) ---------- */
    ldr     x8, =FB_LOGO
    movz    x3, #0x9400
    movk    x3, #0x11, lsl #16              /* 1152000 */
    mov     w4, #0xFF
    lsl     w4, w4, #24
7:
    str     w4, [x8], #4
    subs    x3, x3, #1
    b.ne    7b

    /* ---------- 4. dibujar texto (escritura secuencial) ---------- */
    ldr     x8, =FB_LOGO
    mov     x17, #0                         /* y de pantalla (x19 = &boot_args) */
9:
    mov     x20, #0                         /* x de pantalla */
10:
    mov     x21, x20
    mov     x23, #24
    udiv    x21, x21, x23                   /* columna de caracter */
    cmp     x21, #30
    b.ge    15f

    mov     x6, x17
    mov     x23, #32
    udiv    x6, x6, x23                     /* x6 = fila de caracter (x24 es image_base) */
    cmp     x6, #3
    b.ge    15f

    mov     x0, x21
    mov     x1, x6
    bl      get_char                        /* w0 = ASCII */

    /* gx = (x % 24) / 4 */
    mov     x25, x20
    mov     x23, #24
    udiv    x29, x25, x23
    mul     x29, x29, x23
    sub     x25, x25, x29
    mov     x26, #4
    udiv    x25, x25, x26
    /* gy = (y % 32) / 4 */
    mov     x27, x17
    mov     x23, #32
    udiv    x29, x27, x23
    mul     x29, x29, x23
    sub     x27, x27, x29
    mov     x28, #4
    udiv    x27, x27, x28

    cmp     x25, #5
    b.eq    15f
    cmp     x27, #7
    b.eq    15f

    bl      glyph_bit                       /* w0 = 0 o 1 */
    cmp     w0, #0
    b.eq    15f

    mov     w5, #0xFF
    strb    w5, [x8], #1
    strb    w5, [x8], #1
    strb    w5, [x8], #1
    strb    w5, [x8], #1
    b       16f
15:
    strb    wzr, [x8], #1
    strb    wzr, [x8], #1
    strb    wzr, [x8], #1
    mov     w5, #0xFF
    strb    w5, [x8], #1
16:
    add     x20, x20, #1
    cmp     x20, #ROW_PX
    b.lo    10b
    add     x17, x17, #1
    cmp     x17, #96
    b.lo    9b

    /* ---------- 5. limpiar cache ---------- */
    movz    x21, #0x1880
    movk    x21, #0x1, lsl #16
    ldr     x22, =FB_LOGO
11:
    dc      cvac, x22
    add     x22, x22, #64
    subs    x21, x21, #1
    b.ne    11b
    dsb     sy

    /* ---------- 6. handoff estilo _start de XNU ---------- */
    mov     x0, x19                         /* x0 = &boot_args (x19 preservado) */
    ldr     x22, [sp], #16                  /* recuperar FDT */
    movz    x2, #(STOCK_ENTRY & 0xffff)
    movk    x2, #((STOCK_ENTRY >> 16) & 0xffff), lsl #16
    add     x23, x24, x2                    /* x23 = stext, para volver */
    mov     x20, x13                        /* justo tras el NUL del reporte */
    adr     x2, xnu_entry
    br      x2

    .ltorg

/* ---------- fase B: pseudo _start de XNU (SONDA, no XNU real) ---------- */
xnu_entry:
    mov     w5, #0                          /* 0 = fallo, 1 = todo bien */
    cmp     x0, x19                         /* x0 debe ser &boot_args */
    b.ne    50f
    ldr     w7, [x0]
    ldr     w8, =0x00020002                 /* Revision=2, Version=2 */
    cmp     w7, w8
    b.ne    50f
    ldr     x9, [x0, #96]                   /* deviceTreeP */
    ldr     w10, [x9]
    ldr     w11, =0xEDFE0DD0
    cmp     w10, w11
    b.ne    50f
    mov     w5, #1
50:
    cmp     w5, #1
    b.ne    51f
    adr     x7, ok_str
    mov     w8, #6                          /* ":XNUOK" */
    b       52f
51:
    adr     x7, bad_str
    mov     w8, #7                          /* ":XNUBAD" */
52:
    mov     x12, x20
53:
    ldrb    w13, [x7], #1
    strb    w13, [x12], #1
    subs    w8, w8, #1
    b.ne    53b
    strb    wzr, [x12]

    /* franja de estado en pantalla: y=96..127, 720 px/fila */
    ldr     x8, =FB_LOGO
    movz    x9, #0x3800
    movk    x9, #0x4, lsl #16               /* 0x43800 = 96*720*4 */
    add     x8, x8, x9
    cmp     w5, #1
    b.ne    54f
    ldr     w6, =0xFF00FF00                 /* BGRA: B=0,G=FF,R=0,A=FF = verde */
    b       55f
54:
    ldr     w6, =0xFFFF0000                 /* BGRA: B=0,G=0,R=FF,A=FF = rojo */
55:
    movz    x7, #0x5A00                     /* 23040 pixeles = 32*720 */
56:
    str     w6, [x8], #4
    subs    x7, x7, #1
    b.ne    56b

    /* limpiar cache de nuevo: la franja se escribio despues del primer cvac */
    movz    x9, #0x1880
    movk    x9, #0x1, lsl #16
    ldr     x8, =FB_LOGO
57:
    dc      cvac, x8
    add     x8, x8, #64
    subs    x9, x9, #1
    b.ne    57b
    dsb     sy

    mov     x0, x22                         /* FDT para Linux */
    br      x23                             /* volver a stext */
    .ltorg

/* get_char: x0=col, x1=row -> w0=ASCII */
    .type get_char, %function
get_char:
    str     x30, [sp, #-16]!
    cmp     x1, #0
    b.ne    30f
    adr     x2, line0
    b       31f
30:
    cmp     x1, #1
    b.ne    32f
    adr     x2, line1
    b       31f
32:
    adr     x2, line2
31:
    ldrb    w0, [x2, x0]
    ldr     x30, [sp], #16
    ret
    .size get_char, .-get_char

/* glyph_bit: w0=ASCII, x25=gx, x27=gy -> w0=bit */
    .type glyph_bit, %function
glyph_bit:
    str     x30, [sp, #-16]!
    mov     w2, w0
    mov     w3, #'0'
    sub     w2, w2, w3
    cmp     w2, #43
    b.hs    40f
    adr     x3, font_table
    add     x3, x3, x2, lsl #2
    add     x3, x3, x2
    b       41f
40:
    adr     x3, font_blank
41:
    ldrb    w4, [x3, x25]
    mov     w5, #7
    sub     w5, w5, w27
    lsr     w4, w4, w5
    and     w0, w4, #1
    ldr     x30, [sp], #16
    ret
    .size glyph_bit, .-glyph_bit

cmdline:
    .asciz  "debug=0x8 kext-dev-mode=1"
report_prefix:
    .asciz  "FB:"
hexchars:
    .ascii  "0123456789abcdef"
ok_str:
    .asciz  ":XNUOK"
bad_str:
    .asciz  ":XNUBAD"

line0:  .ascii "XNU A03 FB UART   "
line1:  .ascii "BA CK 0123456789A "
line2:  .ascii "RET OK            "

font_blank: .byte 0,0,0,0,0

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
