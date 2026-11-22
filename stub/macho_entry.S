/*
 * macho_entry.S — entry del Image sintetico para loader Mach-O.
 *
 * code0 = b 0x80000. image_base = PC_real - 0x80000. Sin stack.
 * El payload contiene: loader + Mach-O + DTB crudo.
 *
 * x20 = PC real
 * x21 = entry fisico del kernelcache (devuelto por C)
 * x22 = image_base
 * x23/x24 = macho src/len
 * x25/x26 = dtb src/len
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x00080000
    .equ BOOTARGS_PA, 0x92000000

_start:
    /* Stack temporal: el C del parser Mach-O si usa spill de registros.
     * 0x93000000 esta libre (boot_args 0x92000000, DTB 0x92001000..0x9205BE11). */
    movz    x9, #0
    movk    x9, #0x9300, lsl #16            /* 0x93000000 */
    mov     sp, x9

    adr     x20, _start
    movz    x22, #(PAYLOAD_VMA & 0xffff)
    movk    x22, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x22, x20, x22                   /* image_base */

    adr     x23, macho_off_word
    ldr     w23, [x23]
    add     x23, x20, x23
    adr     x24, macho_len_word
    ldr     w24, [x24]

    adr     x25, dtb_off_word
    ldr     w25, [x25]
    add     x25, x20, x25
    adr     x26, dtb_len_word
    ldr     w26, [x26]

    mov     x0, x22
    mov     x1, x23
    mov     x2, x24
    mov     x3, x25
    mov     x4, x26
    bl      macho_main                      /* x0 = entry fisico, o 0 */

    cmp     x0, #0
    b.eq    fail_hang
    mov     x21, x0

    movz    x0, #(BOOTARGS_PA & 0xffff)
    movk    x0, #((BOOTARGS_PA >> 16) & 0xffff), lsl #16
    br      x21                             /* x0 = &boot_args, como _start */

fail_hang:
    wfe
    b       fail_hang

    .ltorg

    .balign 8
macho_off_word: .word 0xDEADBEEF
macho_len_word: .word 0xDEADBEEF
dtb_off_word:   .word 0xDEADBEEF
dtb_len_word:   .word 0xDEADBEEF

    .size _start, .-_start
