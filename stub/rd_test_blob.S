/*
 * rd_test_blob.S — blob de prueba cargado desde el ramdisk.
 *
 * Enlazado en 0xA1000000. El loader salta aqui con:
 *   x0 = image_base del kernel Linux
 *   x1 = FDT
 *   x2 = stext del kernel Linux (retorno)
 *
 * Hace:
 *   1. escribir "RL:OK" en linux_proc_banner (/proc/version);
 *   2. dibujar una franja AZUL en y=128..159 del framebuffer;
 *   3. dc cvac sobre la franja;
 *   4. volver a stext con x0 = FDT.
 *
 * La franja azul aparece DEBAJO de la franja verde del handoff (y=96..127),
 * asi que es evidente que este codigo se ejecuto DESPUES de la copia a RAM.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PROC_OFF, 0x010623A0
    .equ FB_LOGO,  0x9E000000
    .equ ROW_PX,   720
    .equ BAR_Y0,   128
    .equ BAR_Y1,   160
    .equ BAR_OFF,  (BAR_Y0 * ROW_PX * 4)      /* 0x5A000 */

_start:
    mov     x19, x0                         /* x19 = image_base */
    mov     x20, x1                         /* x20 = FDT */
    mov     x21, x2                         /* x21 = stext */

    /* ---------- 1. marcador RL:OK ---------- */
    movz    x10, #(PROC_OFF & 0xffff)
    movk    x10, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x10, x19, x10
    mov     w11, #'R'
    strb    w11, [x10], #1
    mov     w11, #'L'
    strb    w11, [x10], #1
    mov     w11, #':'
    strb    w11, [x10], #1
    mov     w11, #'O'
    strb    w11, [x10], #1
    mov     w11, #'K'
    strb    w11, [x10], #1
    strb    wzr, [x10]

    /* ---------- 2. franja azul y=128..159 ---------- */
    ldr     x8, =FB_LOGO
    movz    x9, #(BAR_OFF & 0xffff)
    movk    x9, #((BAR_OFF >> 16) & 0xffff), lsl #16
    add     x8, x8, x9
    ldr     w6, =0xFF0000FF                 /* BGRA: B=FF,G=0,R=0,A=FF = azul */
    movz    x7, #0xF000                     /* 61440 pixeles = 32*720 */
1:
    str     w6, [x8], #4
    subs    x7, x7, #1
    b.ne    1b

    /* ---------- 3. coherencia (3840 lineas de 64 bytes) ---------- */
    sub     x8, x8, #245760                 /* volver al inicio de la franja */
    movz    x9, #0xF00                      /* 3840 lineas */
2:
    dc      cvac, x8
    add     x8, x8, #64
    subs    x9, x9, #1
    b.ne    2b
    dsb     sy

    /* ---------- 4. volver a stext ---------- */
    mov     x0, x20                         /* FDT */
    br      x21

    .ltorg
    .size _start, .-_start
