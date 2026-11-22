/*
 * fb_console_seq.S — consola framebuffer con ESCRITURA SECUENCIAL.
 *
 * Metodo probado: el detector de stride escribio secuencialmente desde
 * 0x9E000000 con 4 bytes/pixel y 1600 pixeles/fila y funciono.
 * Esta consola hace lo mismo: recorre la pantalla fila por fila, y en cada
 * fila escribe los pixeles de izquierda a derecha, sin mul para direcciones.
 *
 * Diseno:
 *   - fuente 5x7 por columna (cada byte = columna, bit = fila, MSB arriba)
 *   - escala 4x: cada glyph bit = 4x4 pixeles
 *   - celda de caracter = 6*4 = 24 px ancho, 8*4 = 32 px alto
 *   - 3 lineas de texto, escritas en las primeras 3 filas de caracteres
 *
 * Para evitar cualquier mul, se procesa la pantalla como un stream:
 *   para cada fila de pantalla y=0..31*3:
 *     para cada columna de pantalla x=0..1599:
 *       determinar si ese pixel debe ser blanco o negro segun el texto
 *
 * Eso es lento pero simple y corregible.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ FB_LOGO, 0x9E000000
    .equ ROW_PX,  720                       /* ancho real del buffer (vertical) */
    .equ TOTAL_PX, 1152000                  /* 720*1600 = 1152000 */

_start:
    /* ---------- boot_args y /proc/version ---------- */
    mov     x22, x0
    /* (se omiten para simplificar; la consola es solo visual) */

    /* ---------- borrar todo a negro opaco (secuencial) ---------- */
    ldr     x8, =FB_LOGO
    movz    x3, #0x9400
    movk    x3, #0x11, lsl #16
    mov     w4, #0xFF
    lsl     w4, w4, #24
1:
    str     w4, [x8], #4
    subs    x3, x3, #1
    b.ne    1b

    /* ---------- dibujar texto ---------- */
    /* x8 apunta al inicio del framebuffer otra vez */
    ldr     x8, =FB_LOGO

    /* y = 0 .. 95 (3 lineas * 32 px) */
    mov     x19, #0                         /* y de pantalla */
2:
    /* x = 0 .. 1599 */
    mov     x20, #0                         /* x de pantalla */
3:
    /* determinar caracter: char_col = x / 24 */
    mov     x21, x20
    mov     x23, #24
    udiv    x21, x21, x23                   /* x21 = columna de caracter */
    cmp     x21, #30
    b.ge    10f                             /* fuera del texto -> negro */

    /* fila de caracter = y / 32 */
    mov     x24, x19
    mov     x23, #32
    udiv    x24, x24, x23                   /* x24 = fila de caracter (0..2) */
    cmp     x24, #3
    b.ge    10f

    /* obtener el caracter en (fila=x24, col=x21) */
    mov     x0, x21
    mov     x1, x24
    bl      get_char                        /* w0 = ASCII */

    /* dentro del glyph: gx = (x%24)/4 = 0..5, gy = (y%32)/4 = 0..7 */
    mov     x25, x20
    mov     x23, #24
    udiv    x29, x25, x23                   /* x/24 */
    mul     x29, x29, x23
    sub     x25, x25, x29                   /* x%24 */
    mov     x26, #4
    udiv    x25, x25, x26                   /* gx = 0..5 */

    mov     x27, x19
    mov     x23, #32
    udiv    x29, x27, x23                   /* y/32 */
    mul     x29, x29, x23
    sub     x27, x27, x29                   /* y%32 */
    mov     x28, #4
    udiv    x27, x27, x28                   /* gy = 0..7 */

    /* si gx==5 o gy==7 -> pixel de separacion (negro) */
    cmp     x25, #5
    b.eq    10f
    cmp     x27, #7
    b.eq    10f

    /* glyph columna = gx (0..4), fila = gy (0..6) */
    bl      glyph_bit                       /* w0 = 0 o 1 */
    cmp     w0, #0
    b.eq    10f

    /* pixel blanco */
    mov     w5, #0xFF
    strb    w5, [x8], #1
    strb    w5, [x8], #1
    strb    w5, [x8], #1
    strb    w5, [x8], #1
    b       11f
10:
    /* pixel negro opaco */
    strb    wzr, [x8], #1
    strb    wzr, [x8], #1
    strb    wzr, [x8], #1
    mov     w5, #0xFF
    strb    w5, [x8], #1
11:
    add     x20, x20, #1
    cmp     x20, #ROW_PX
    b.lo    3b
    add     x19, x19, #1
    cmp     x19, #96
    b.lo    2b

    /* seguir rellenando el resto del buffer a negro opaco */
    /* ya esta todo a negro del borrado inicial, saltar limpieza */

    /* limpiar cache */
    movz    x21, #0x1880
    movk    x21, #0x1, lsl #16
    ldr     x22, =FB_LOGO
12:
    dc      cvac, x22
    add     x22, x22, #64
    subs    x21, x21, #1
    b.ne    12b
    dsb     sy

13:
    wfe
    b       13b

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
    add     x3, x3, x2                      /* &font[ch*5] */
    b       41f
40:
    adr     x3, font_blank
41:
    ldrb    w4, [x3, x25]                   /* columna gx */
    mov     w5, #7
    sub     w5, w5, w27                     /* MSB arriba: bit = 7-gy */
    lsr     w4, w4, w5
    and     w0, w4, #1
    ldr     x30, [sp], #16
    ret
    .size glyph_bit, .-glyph_bit

    .ltorg

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
