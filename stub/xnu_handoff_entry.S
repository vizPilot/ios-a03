/*
 * xnu_handoff_entry.S — entry del Image sintetico con handoff estilo _start.
 *
 * LK entra con MMU off. code0 = b 0x80000, asi que:
 *   image_base = PC_real - 0x80000
 *
 * El payload contiene: loader + blob + DTB crudo. Cuatro palabras 0xDEADBEEF
 * se parchean en build con los offsets/longitudes del blob y del DTB.
 *
 * No se usa el stack (en el kernel sintetico no podemos asumir SP valido).
 *
 * Registros:
 *   x20 = PC real del payload
 *   x21 = entry del blob (devuelto por C)
 *   x22 = image_base
 *   x23/x24 = blob src/len
 *   x25/x26 = dtb src/len
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x00080000
    .equ BOOTARGS_PA, 0x92000000

_start:
    adr     x20, _start
    movz    x22, #(PAYLOAD_VMA & 0xffff)
    movk    x22, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x22, x20, x22                   /* x22 = image_base */

    adr     x23, blob_off_word
    ldr     w23, [x23]
    add     x23, x20, x23                   /* blob src */
    adr     x24, blob_len_word
    ldr     w24, [x24]                      /* blob len */

    adr     x25, dtb_off_word
    ldr     w25, [x25]
    add     x25, x20, x25                   /* dtb src */
    adr     x26, dtb_len_word
    ldr     w26, [x26]                      /* dtb len */

    mov     x0, x22                         /* image_base */
    mov     x1, x23                         /* blob src */
    mov     x2, x24                         /* blob len */
    mov     x3, x25                         /* dtb src */
    mov     x4, x26                         /* dtb len */
    bl      handoff_main                    /* x0 = entry del blob */

    mov     x21, x0                         /* conservar entry */

    /* x0 = &boot_args, exactamente como _start de XNU */
    movz    x0, #(BOOTARGS_PA & 0xffff)
    movk    x0, #((BOOTARGS_PA >> 16) & 0xffff), lsl #16

    br      x21

    .ltorg

    .balign 8
blob_off_word:  .word 0xDEADBEEF
blob_len_word:  .word 0xDEADBEEF
dtb_off_word:   .word 0xDEADBEEF
dtb_len_word:   .word 0xDEADBEEF

    .size _start, .-_start
