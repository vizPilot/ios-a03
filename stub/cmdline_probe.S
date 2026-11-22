/*
 * cmdline_probe.S — prueba decisiva de ejecución en EL1.
 *
 * LK entra al kernel con x0 = &boot_args (physical), MMU off.
 * Este payload:
 *   1. añade " androidboot.xnuprobe=1" al final de boot_args.CommandLine;
 *   2. salta al entry real del kernel stock (0x1208000).
 *
 * Si Android arranca y `getprop ro.boot.xnuprobe` devuelve 1, entonces:
 *   - LK acepta un kernel modificado;
 *   - nuestro código se ejecuta antes que Linux;
 *   - podemos seguir con el loader estilo iBoot para XNU.
 *
 * No se toca x0: el kernel recibe el mismo boot_args pointer.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ BOOTARGS_CMDLINE_OFF, 108
    .equ STOCK_KERNEL_ENTRY,   0x01208000  /* PC=0x8000 + offset 0x01200000 */

_start:
    mov     x19, x0                      /* boot_args physical */
    add     x20, x19, #BOOTARGS_CMDLINE_OFF

    /* buscar el NUL final de CommandLine */
1:
    ldrb    w21, [x20]
    cbnz    w21, 2f
    b       3f
2:
    add     x20, x20, #1
    b       1b
3:
    /* x20 apunta al NUL; copiar la cadena nueva incluido su NUL */
    adr     x22, probe_str
4:
    ldrb    w21, [x22], #1
    strb    w21, [x20], #1
    cbnz    w21, 4b

    /* saltar al kernel stock sin alterar x0 */
    ldr     x23, =STOCK_KERNEL_ENTRY
    br      x23

    .balign 8
probe_str:
    .asciz  " androidboot.xnuprobe=1"
    .size _start, .-_start
