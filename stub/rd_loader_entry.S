/*
 * rd_loader_entry.S — entry del loader que copia un blob embebido a RAM.
 *
 * Entra desde code0 con MMU off. x0 = FDT cargado por LK.
 *
 * El blob va justo despues del loader dentro del payload del kernel. Dos
 * palabras 0xDEADBEEF se parchean en build con el offset y la longitud.
 *
 * Registros:
 *   x20 = PC real / entry del blob
 *   x21 = FDT
 *   x22 = image_base (callee-saved, sobrevive a la llamada C)
 *   x23 = origen del blob
 *   x24 = longitud del blob
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x0169E810
    .equ STOCK_ENTRY, 0x01200000

_start:
    mov     x21, x0                         /* x21 = FDT */
    str     x21, [sp, #-16]!                /* conservar FDT */

    adr     x20, _start                     /* PC real del payload */
    movz    x22, #(PAYLOAD_VMA & 0xffff)
    movk    x22, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x22, x20, x22                   /* x22 = image_base */

    adr     x23, blob_off_word
    ldr     w23, [x23]                      /* offset del blob desde _start */
    add     x23, x20, x23                   /* x23 = origen del blob */
    adr     x24, blob_len_word
    ldr     w24, [x24]                      /* longitud del blob */

    mov     x0, x22                         /* arg0 = image_base */
    mov     x1, x21                         /* arg1 = FDT */
    mov     x2, x23                         /* arg2 = origen del blob */
    mov     x3, x24                         /* arg3 = longitud */
    bl      rd_loader_main                  /* x0 = entry del blob, o 0 */

    mov     x20, x0                         /* entry */
    ldr     x21, [sp], #16                  /* recuperar FDT */

    movz    x2, #(STOCK_ENTRY & 0xffff)
    movk    x2, #((STOCK_ENTRY >> 16) & 0xffff), lsl #16
    add     x2, x22, x2                     /* x2 = stext */

    cmp     x20, #0
    b.eq    2f

    mov     x0, x22
    mov     x1, x21
    br      x20

2:
    mov     x0, x21
    br      x2

    .ltorg

    .balign 8
blob_off_word:
    .word   0xDEADBEEF
blob_len_word:
    .word   0xDEADBEEF

    .size _start, .-_start
