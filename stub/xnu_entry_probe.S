/*
 * xnu_entry_probe.S — valida el handoff final a _start de XNU.
 *
 * Fase A: construye boot_args (igual que bootargs_loader.S) y en lugar de
 * volver a Linux:
 *   x0 = &boot_args (0x92000000)
 *   x23 = stext del kernel stock (para poder volver)
 *   x20 = puntero justo despues del reporte en linux_proc_banner
 *   salta a xnu_entry
 *
 * Fase B: simula _start de XNU:
 *   - comprueba x0 == 0x92000000
 *   - comprueba Revision/Version == 2/2
 *   - comprueba que deviceTreeP apunta a un FDT valido
 *   - escribe ":XNUOK" o ":XNUBAD" en /proc/version
 *   - vuelve a stext (x23)
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x0169E810
    .equ STOCK_ENTRY, 0x01200000
    .equ DELTA,       (PAYLOAD_VMA - STOCK_ENTRY)
    .equ BA_DST,      0x92000000
    .equ PROC_OFF,    0x010623A0
    .equ BA_WORDS,    144

_start:
    mov     x22, x0
    adr     x23, _start
    movz    x24, #(PAYLOAD_VMA & 0xffff)
    movk    x24, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x24, x23, x24                  /* x24 = image_base */

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

    mov     x9, x19
    mov     x10, #BA_WORDS
    mov     x11, #0
4:
    ldr     x12, [x9], #8
    add     x11, x11, x12
    subs    x10, x10, #1
    b.ne    4b

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

    movz    x13, #(PROC_OFF & 0xffff)
    movk    x13, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x13, x24, x13

    adr     x14, report_prefix
5:
    ldrb    w15, [x14], #1
    strb    w15, [x13], #1
    cbnz    w15, 5b
    sub     x13, x13, #1

    adr     x16, hexchars
    mov     x17, #16
6:
    sub     x17, x17, #1
    lsl     x18, x17, #2
    lsr     x12, x11, x18
    and     x12, x12, #0xf
    ldrb    w12, [x16, x12]
    strb    w12, [x13], #1
    cbnz    x17, 6b
    strb    w20, [x13], #1
    strb    wzr, [x13]

    /* ---------- handoff estilo XNU ---------- */
    mov     x0, x19                        /* x0 = &boot_args */
    movz    w24, #(DELTA & 0xffff)
    movk    w24, #((DELTA >> 16) & 0xffff), lsl #16
    sub     x23, x23, x24                  /* x23 = stext, para volver */
    mov     x20, x13                       /* justo tras el NUL del reporte */
    adr     x24, xnu_entry
    br      x24

/* ---------- fase B: pseudo _start de XNU ---------- */
xnu_entry:
    mov     w5, #0                         /* 0 = fallo, 1 = todo bien */
    cmp     x0, x19
    b.ne    9f
    ldr     w7, [x0]
    ldr     w8, =0x00020002                /* Revision=2, Version=2 */
    cmp     w7, w8
    b.ne    9f
    ldr     x9, [x0, #96]                  /* deviceTreeP */
    ldr     w10, [x9]
    ldr     w11, =0xEDFE0DD0
    cmp     w10, w11
    b.ne    9f
    mov     w5, #1
9:
    cmp     w5, #1
    b.ne    10f
    adr     x7, ok_str
    mov     w8, #7                         /* ":XNUOK" */
    b       11f
10:
    adr     x7, bad_str
    mov     w8, #8                         /* ":XNUBAD" */
11:
    mov     x12, x20
12:
    ldrb    w13, [x7], #1
    strb    w13, [x12], #1
    subs    w8, w8, #1
    b.ne    12b
    strb    wzr, [x12]

    mov     x0, x22                        /* restaurar x0 = FDT para Linux */
    br      x23                            /* volver al kernel stock */

    .ltorg

cmdline:
    .asciz  "debug=0x8 kext-dev-mode=1"
report_prefix:
    .asciz  "BA:"
ok_str:
    .asciz  ":XNUOK"
bad_str:
    .asciz  ":XNUBAD"
hexchars:
    .ascii  "0123456789abcdef"

    .size _start, .-_start
