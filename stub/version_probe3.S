/*
 * version_probe3.S — igual que version_probe2 pero con marcador unico.
 *
 * Se usa "XZ" en lugar de "XN" para poder distinguirlo del control
 * kernel-string-only2-boot.img, que also muestra "XN version ...".
 *
 * 1. image_base = PC_actual - 0x169e810;
 * 2. "%s" -> "XZ" en linux_proc_banner (0x10623a0);
 * 3. salto a stext (image_base + 0x1200000) con x0 intacto.
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
    sub     x24, x23, x24                  /* image_base */

    movz    x25, #(PROC_OFF & 0xffff)
    movk    x25, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x25, x24, x25

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
    .ascii  "XZ"
    .size _start, .-_start
