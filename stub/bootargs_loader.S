/*
 * bootargs_loader.S — loader de fase 1: construir struct boot_args.
 *
 * Entra desde code0 con MMU off. x0 es (segun el protocolo ARM64) la
 * direccion fisica del FDT cargado por LK; se guarda en x22 y se restaura
 * antes de saltar al kernel stock.
 *
 * No se incrusta el DTB: no cabe antes del trailer Samsung (solo quedan
 * ~5 KB libres). En su lugar se usa el FDT que ya cargo LK y se valida
 * su magic en el propio payload.
 *
 * Hace:
 *   1. construir boot_args XNU en 0x92000000 (con deviceTreeP = x0);
 *   2. calcular un checksum de los campos fijos;
 *   3. escribir "BA:<checksum>:D" (o ":X" si el magic falla) en
 *      linux_proc_banner, legible con `cat /proc/version`;
 *   4. saltar a stext del kernel stock con x0 intacto.
 *
 * Fuentes: xnu-10063.141.1/pexpert/pexpert/arm64/boot.h y
 *          xnu-10063.141.1/makedefs/MakeInc.def
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
    .equ BA_WORDS,    144                 /* 1152 / 8 */

_start:
    mov     x22, x0                        /* conservar x0 (FDT) */
    adr     x23, _start
    movz    x24, #(PAYLOAD_VMA & 0xffff)
    movk    x24, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x24, x23, x24                  /* x24 = image_base */

    /* ---------- 1. construir boot_args ---------- */
    movz    x19, #(BA_DST & 0xffff)
    movk    x19, #((BA_DST >> 16) & 0xffff), lsl #16

    mov     x5, #BA_WORDS
    mov     x6, x19
2:
    str     xzr, [x6], #8
    subs    x5, x5, #1
    b.ne    2b

    mov     w5, #2                         /* kBootArgsRevision2 / Version2 */
    strh    w5, [x19, #0]
    strh    w5, [x19, #2]

    ldr     x5, =0xfffffff007004000        /* VM_KERNEL_LINK_ADDRESS */
    str     x5, [x19, #8]                  /* virtBase */

    ldr     x5, =0x0000000080000000        /* physBase */
    str     x5, [x19, #16]

    ldr     x5, =0x00000000fffff000        /* memSize */
    str     x5, [x19, #24]
    str     x5, [x19, #1144]               /* memSizeActual */

    adr     x6, cmdline
    add     x7, x19, #108
3:
    ldrb    w8, [x6], #1
    strb    w8, [x7], #1
    cbnz    w8, 3b

    /* ---------- 2. checksum de los campos fijos ---------- */
    mov     x9, x19
    mov     x10, #BA_WORDS
    mov     x11, #0                        /* x11 = checksum */
4:
    ldr     x12, [x9], #8
    add     x11, x11, x12
    subs    x10, x10, #1
    b.ne    4b

    /* ---------- 3. FDT: deviceTreeP / deviceTreeLength ---------- */
    ldr     w5, [x22]                      /* magic leido como LE */
    ldr     w6, [x22, #4]                  /* totalsize (BE) */
    rev     w6, w6
    mov     w20, #'X'                      /* marcador por defecto: magic malo */
    ldr     w21, =0xEDFE0DD0               /* 0xD00DFEED en LE */
    cmp     w5, w21
    b.ne    8f
    mov     w20, #'D'
8:
    str     x22, [x19, #96]                /* deviceTreeP */
    str     w6, [x19, #104]                /* deviceTreeLength */

    /* ---------- 4. reporte en /proc/version ---------- */
    movz    x13, #(PROC_OFF & 0xffff)
    movk    x13, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x13, x24, x13                  /* x13 = linux_proc_banner */

    adr     x14, report_prefix
5:
    ldrb    w15, [x14], #1
    strb    w15, [x13], #1
    cbnz    w15, 5b
    sub     x13, x13, #1                   /* sobreescribir el NUL */

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

    /* marcador del FDT calculado en el paso 3 */
    strb    w20, [x13], #1
    strb    wzr, [x13]

    /* ---------- 5. volver al kernel stock ---------- */
    mov     x0, x22
    movz    w24, #(DELTA & 0xffff)
    movk    w24, #((DELTA >> 16) & 0xffff), lsl #16
    sub     x23, x23, x24
    br      x23

    .ltorg

cmdline:
    .asciz  "debug=0x8 kext-dev-mode=1"
report_prefix:
    .asciz  "BA:"
hexchars:
    .ascii  "0123456789abcdef"

    .size _start, .-_start
