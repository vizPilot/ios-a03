/*
 * version_probe2.S — prueba de ejecucion real del payload en EL1.
 *
 * El control anterior demostro que el kernel flasheado es el nuestro:
 * al parchear linux_proc_banner (offset 0x10623a0) /proc/version cambio.
 * El intento anterior miro la cadena equivocada (linux_banner, solo dmesg).
 *
 * Este payload:
 *   1. calcula image_base = PC_actual - 0x169e810;
 *   2. cambia "%s" por "XN" en linux_proc_banner (offset 0x10623a0);
 *   3. salta a stext (image_base + 0x1200000) con x0 intacto.
 *
 * Si /proc/version muestra "XN version Linux ...", nuestro codigo corrio
 * en EL1 antes que Linux.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x0169E810
    .equ STOCK_ENTRY, 0x01200000
    .equ PROC_OFF,    0x010623A0
    .equ DELTA,       (PAYLOAD_VMA - STOCK_ENTRY)

_start:
    adr     x23, _start
    movz    x24, #(PAYLOAD_VMA & 0xffff)
    movk    x24, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x24, x23, x24                  /* x24 = image_base */

    movz    x25, #(PROC_OFF & 0xffff)
    movk    x25, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x25, x24, x25                  /* x25 = linux_proc_banner */

    adr     x26, marker
    mov     w27, #2
1:
    ldrb    w28, [x26], #1
    strb    w28, [x25], #1
    subs    w27, w27, #1
    b.ne    1b

    movz    w24, #(DELTA & 0xffff)
    movk    w24, #((DELTA >> 16) & 0xffff), lsl #16
    sub     x23, x23, x24
    br      x23

    .balign 8
marker:
    .ascii  "XN"
    .size _start, .-_start
