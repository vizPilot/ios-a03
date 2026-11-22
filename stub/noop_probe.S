/*
 * noop_probe.S — test minimo del kernel modificado.
 *
 * No toca nada: solo salta al entry real del kernel stock (0x01208000).
 * Si este boot.img arranca, LK acepta kernels modificados y nuestro payload
 * corre en EL1; el fallo anterior estuvo en el parcheo de la cmdline.
 * Si entra en bucle, LK verifica el kernel y hay que usar kexec.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ STOCK_KERNEL_ENTRY, 0x01208000

_start:
    ldr     x23, =STOCK_KERNEL_ENTRY
    br      x23
    .size _start, .-_start
