/*
 * synth_test_blob.S — blob de prueba para el kernel sintetico.
 *
 * Enlazado en 0xA1000000. El loader salta aqui con:
 *   x0 = image_base del Image sintetico
 *   x1 = base del Image (no se usa)
 *   x2 = origen del blob
 *   x3 = longitud del blob
 *
 * No hay Linux al que volver: dibuja una franja MAGENTA ancha en el
 * framebuffer y se queda en wfe. Si la franja aparece, el Image sintetico
 * fue aceptado por LK, el loader corrio y el salto a RAM funciono.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ FB_LOGO,  0x9E000000
    .equ ROW_PX,   720
    .equ BAR_Y0,   200
    .equ ROWS,     200
    .equ BAR_OFF,  (BAR_Y0 * ROW_PX * 4)      /* 0x95800 */

_start:
    /* franja magenta y=200..399, todo el ancho */
    ldr     x8, =FB_LOGO
    movz    x9, #(BAR_OFF & 0xffff)
    movk    x9, #((BAR_OFF >> 16) & 0xffff), lsl #16
    add     x8, x8, x9
    ldr     w6, =0xFFFF00FF                 /* BGRA: B=FF,G=0,R=FF,A=FF = magenta */
    ldr     x7, =(ROWS * ROW_PX)            /* 144000 pixeles */
1:
    str     w6, [x8], #4
    subs    x7, x7, #1
    b.ne    1b

    /* coherencia: 200*720*4 = 576000 bytes = 9000 lineas de 64 */
    movz    x10, #((ROWS * ROW_PX * 4) & 0xffff)
    movk    x10, #(((ROWS * ROW_PX * 4) >> 16) & 0xffff), lsl #16
    sub     x8, x8, x10                     /* 576000 bytes */
    movz    x9, #(ROWS * ROW_PX / 16)       /* 9000 */
2:
    dc      cvac, x8
    add     x8, x8, #64
    subs    x9, x9, #1
    b.ne    2b
    dsb     sy
    isb     sy

    /* no hay Linux: congelar aqui */
3:
    wfe
    b       3b

    .ltorg
    .size _start, .-_start
