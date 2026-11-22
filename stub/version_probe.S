/*
 * version_probe.S — prueba de que nuestro payload SI se ejecuta en EL1.
 *
 * El noop probe demostro que un kernel modificado arranca, pero no probaba
 * que nuestro codigo corriera (LK podria ignorar code0). Este payload:
 *
 *   1. calcula image_base = PC_actual - 0x169e810;
 *   2. reemplaza "Linux" por "XNU  " en la cadena de /proc/version,
 *      que esta en el offset 0x1062248 del kernel stock;
 *   3. salta a stext (offset 0x1200000) con x0 intacto.
 *
 * Si `cat /proc/version` muestra "XNU   version 4.14...", nuestro codigo
 * corrio en EL1 antes que Linux y puede usarse como loader de XNU.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x0169E810   /* == longitud del kernel stock */
    .equ STOCK_ENTRY, 0x01200000   /* stext, relativo a image_base */
    .equ VERSION_OFF, 0x01062248   /* "Linux version 4.14.199..." */
    .equ DELTA,       (PAYLOAD_VMA - STOCK_ENTRY)

_start:
    /* x23 = direccion real del payload; x24 = image_base */
    adr     x23, _start
    movz    x24, #(PAYLOAD_VMA & 0xffff)
    movk    x24, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x24, x23, x24

    /* x25 = direccion de "Linux version..." dentro del kernel cargado */
    movz    x25, #(VERSION_OFF & 0xffff)
    movk    x25, #((VERSION_OFF >> 16) & 0xffff), lsl #16
    add     x25, x24, x25

    /* parchear 5 bytes: "Linux" -> "XNU  " */
    adr     x26, marker
    mov     w27, #5
1:
    ldrb    w28, [x26], #1
    strb    w28, [x25], #1
    subs    w27, w27, #1
    b.ne    1b

    /* volver a stext: x23 todavia es la direccion del payload */
    movz    w24, #(DELTA & 0xffff)
    movk    w24, #((DELTA >> 16) & 0xffff), lsl #16
    sub     x23, x23, x24
    br      x23

    .balign 8
marker:
    .ascii  "XNU  "
    .size _start, .-_start
