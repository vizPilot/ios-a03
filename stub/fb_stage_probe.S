/*
 * fb_stage_probe.S — confirma por /proc/version si las escrituras al FB ocurren.
 *
 * Escribe marcadores de etapa en linux_proc_banner:
 *   "100" -> entro al payload
 *   "120" -> termine de llenar 0x9E000000 de rojo
 *   "123" -> termine de llenar 0xFD380000 de verde y volvi
 *
 * Luego vuelve a stext. Si /proc/version muestra "123", el payload corre
 * completo y el problema esta en el DPU/IOMMU/panel, no en nuestro codigo.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x0169E810
    .equ STOCK_ENTRY, 0x01200000
    .equ PROC_OFF,    0x010623A0
    .equ NPIX,        1152000                /* 1600*720 = 0x119400 */

_start:
    mov     x22, x0                         /* FDT */
    adr     x23, _start
    movz    x24, #(PAYLOAD_VMA & 0xffff)
    movk    x24, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x24, x23, x24                   /* image_base */

    movz    x13, #(PROC_OFF & 0xffff)
    movk    x13, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x13, x24, x13

    /* estado inicial "100" */
    mov     w15, #'1'
    strb    w15, [x13]
    mov     w15, #'0'
    strb    w15, [x13, #1]
    strb    w15, [x13, #2]
    strb    wzr, [x13, #3]

    /* ---- etapa 1: 0x9E000000 = rojo ---- */
    ldr     x2, =0x9E000000
    movz    x3, #0x9400
    movk    x3, #0x11, lsl #16              /* 1152000 */
    mov     w4, #0xFF
    mov     w5, #0x00
    mov     w6, #0x00
    bl      fill
    mov     w15, #'2'
    strb    w15, [x13, #1]

    /* ---- etapa 2: 0xFD380000 = verde ---- */
    ldr     x2, =0xFD380000
    movz    x3, #0x9400
    movk    x3, #0x11, lsl #16
    mov     w4, #0x00
    mov     w5, #0xFF
    mov     w6, #0x00
    bl      fill
    mov     w15, #'3'
    strb    w15, [x13, #2]

    /* ---- volver a Linux ---- */
    mov     x0, x22
    movz    x2, #(STOCK_ENTRY & 0xffff)
    movk    x2, #((STOCK_ENTRY >> 16) & 0xffff), lsl #16
    add     x2, x24, x2
    br      x2

/* fill: x2 = destino, x3 = nº pixeles, w4/w5/w6 = RGB */
    .type fill, %function
fill:
1:
    strb    w4, [x2], #1
    strb    w5, [x2], #1
    strb    w6, [x2], #1
    subs    x3, x3, #1
    b.ne    1b
    ret
    .size fill, .-fill

    .ltorg
    .size _start, .-_start
