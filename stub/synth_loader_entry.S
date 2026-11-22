/*
 * synth_loader_entry.S — entry del loader para kernel sintetico.
 *
 * Igual que rd_loader_entry.S pero:
 *   - PAYLOAD_VMA = 0x80000 (posicion del payload en el Image minimo)
 *   - no hay Linux al que volver: si falla, se queda en wfe
 *
 * LK entra con x0 = FDT y MMU off. code0 del Image sintetico es
 * "b 0x80000", asi que el PC real - 0x80000 = base del Image.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x00080000

_start:
    adr     x20, _start                     /* PC real del payload */
    movz    x22, #(PAYLOAD_VMA & 0xffff)
    movk    x22, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x22, x20, x22                   /* x22 = base del Image */

    adr     x23, blob_off_word
    ldr     w23, [x23]
    add     x23, x20, x23                   /* origen del blob */
    adr     x24, blob_len_word
    ldr     w24, [x24]                      /* longitud del blob */

    mov     x0, x22                         /* image_base */
    mov     x1, x0                          /* FDT no se usa en modo sintetico */
    mov     x2, x23
    mov     x3, x24
    bl      rd_loader_main

    cmp     x0, #0
    b.eq    2f
    br      x0                              /* exito: saltar al blob */

2:
    wfe                                     /* fallo: congelar para diagnosticar */
    b       2b

    .ltorg

    .balign 8
blob_off_word:
    .word   0xDEADBEEF
blob_len_word:
    .word   0xDEADBEEF

    .size _start, .-_start
