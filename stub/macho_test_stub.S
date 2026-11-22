/*
 * macho_test_stub.S — codigo dentro de un Mach-O sintetico.
 *
 * Se enlaza en 0xA2004000 (KERN_PHYS + 0x4000) y se coloca en el Mach-O
 * en fileoff 0x4000. El loader llama al entry con x0 = &boot_args.
 *
 * Dibuja una franja MAGENTA en y=320..335 para demostrar que el entry del
 * Mach-O cargado se ejecuto. No usa stack.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ FB_LOGO, 0x9E000000
    .equ ROW_BYTES, 2880
    .equ Y0, 320
    .equ Y_OFF, (Y0 * ROW_BYTES)       /* 0xE1000 */

_start:
    ldr     x8, =FB_LOGO
    movz    x9, #(Y_OFF & 0xffff)
    movk    x9, #((Y_OFF >> 16) & 0xffff), lsl #16
    add     x8, x8, x9

    ldr     w10, =0xFFFF00FF            /* magenta BGRA */
    mov     x7, #(16 * 720)
1:
    str     w10, [x8], #4
    subs    x7, x7, #1
    b.ne    1b

    movz    x9, #(16 * ROW_BYTES)       /* 46080 = 0xB400 */
    sub     x8, x8, x9
    mov     x7, #720
2:
    dc      cvac, x8
    add     x8, x8, #64
    subs    x7, x7, #1
    b.ne    2b
    dsb     sy
    isb     sy

3:
    wfe
    b       3b

    .ltorg
    .size _start, .-_start
