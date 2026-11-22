/*
 * noop_probe2.S — test minimo del kernel modificado, version corregida.
 *
 * El intento anterior inyectaba el payload en el offset 0x80000 del kernel,
 * pero ahi hay CODIGO VIVO del kernel (se comprobo desensamblando: hay
 * saltos a 0x7fbc4, es decir, mitad de una funcion). Eso explica el bootloop
 * aunque el payload solo hiciera un salto.
 *
 * El entry real del kernel si esta en el offset 0x1200000:
 *   1200000: bl 0x1200020
 *   1200020: mov x21, x0          <- x0 = boot_args
 *   120002c: stp x21, x1, [x0]    <- guarda boot_args en 0x1515000
 *
 * Este payload se coloca AL FINAL del archivo kernel (offset 0x169e810),
 * sin sobrescribir ni un byte del kernel stock. code0 se cambia a
 * `b 0x169e810` y el payload vuelve a stext con aritmetica relativa al PC,
 * asi que funciona sea cual sea la direccion de carga (image_base).
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    /* payload_offset - stext_offset = 0x169e810 - 0x1200000 */
    .equ DELTA, 0x0049E810

_start:
    adr     x23, _start                 /* x23 = image_base + 0x169e810 */
    movz    w24, #(DELTA & 0xffff)
    movk    w24, #((DELTA >> 16) & 0xffff), lsl #16
    sub     x23, x23, x24               /* x23 = image_base + 0x1200000 */
    br      x23

    .size _start, .-_start
