/*
 * blob_kernel.S — "kernel" sintético para validar el cargador de blob.
 *
 * Se enlaza en 0x92500000. El loader lo copia desde el final del kernel de
 * Linux a esa dirección y salta aquí con:
 *
 *   x0 = &boot_args (0x92000000)
 *   x1 = image_base del kernel Linux (para localizar linux_proc_banner)
 *   x2 = stext del kernel Linux (dirección de retorno)
 *   x22 = FDT (para restaurar x0 antes de volver)
 *
 * Escribe en /proc/version:
 *   BL:<checksum boot_args 16 hex>:<PC real 16 hex>
 *
 * Y por la UART de consola (serial1 @ 0x200b0000, ya inicializada por LK):
 *   A03-BLOB-KERNEL-OK pc=0x............
 *
 * El PC impreso demuestra que el código se ejecuta DESPUÉS de la copia a RAM
 * (si saltáramos al origen, el PC sería la dirección dentro del kernel Linux).
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ UART_BASE,      0x200b0000
    .equ SPRD_TXD,       0x0000
    .equ SPRD_STS1,      0x000C
    .equ TX_FIFO_CNT_MASK, 0xFF00

    .equ PROC_OFF,       0x010623A0
    .equ BA_WORDS,       144                 /* 1152 / 8 */

_start:
    mov     x19, x0                         /* x19 = &boot_args */
    mov     x20, x1                         /* x20 = image_base Linux */
    mov     x21, x2                         /* x21 = stext Linux */
                                            /* x22 = FDT (intacto) */

    /* ---------- checksum de boot_args ---------- */
    mov     x9, x19
    mov     x10, #BA_WORDS
    mov     x11, #0
1:
    ldr     x12, [x9], #8
    add     x11, x11, x12
    subs    x10, x10, #1
    b.ne    1b

    /* PC real de ejecución: debe ser 0x92500000 */
    adr     x13, _start

    /* ---------- /proc/version ---------- */
    movz    x14, #(PROC_OFF & 0xffff)
    movk    x14, #((PROC_OFF >> 16) & 0xffff), lsl #16
    add     x14, x20, x14                   /* x14 = linux_proc_banner */

    adr     x15, report_prefix
2:
    ldrb    w16, [x15], #1
    strb    w16, [x14], #1
    cbnz    w16, 2b
    sub     x14, x14, #1                    /* sobrescribir el NUL */

    adr     x17, hexchars

    /* 16 nibbles del checksum */
    mov     x18, #16
3:
    sub     x18, x18, #1
    lsl     x5, x18, #2
    lsr     x6, x11, x5
    and     x6, x6, #0xf
    ldrb    w6, [x17, x6]
    strb    w6, [x14], #1
    cbnz    x18, 3b

    mov     w6, #':'
    strb    w6, [x14], #1

    /* 16 nibbles del PC */
    mov     x18, #16
4:
    sub     x18, x18, #1
    lsl     x5, x18, #2
    lsr     x6, x13, x5
    and     x6, x6, #0xf
    ldrb    w6, [x17, x6]
    strb    w6, [x14], #1
    cbnz    x18, 4b

    strb    wzr, [x14]

    /* ---------- UART ---------- */
    adr     x0, msg_banner
    bl      print_str
    adr     x0, msg_pc
    bl      print_str
    mov     x19, x13                        /* print_hex64 usa x19 */
    bl      print_hex64
    adr     x0, msg_nl
    bl      print_str

    /* ---------- volver al kernel stock ---------- */
    mov     x0, x22                         /* restaurar x0 = FDT */
    br      x21

/* ------------------------------------------------------------------ */
/* putc: imprime el byte bajo de x0                                    */
/* ------------------------------------------------------------------ */
    .type putc, %function
putc:
    ldr     x16, =UART_BASE
    mov     x9, #256                        /* espera LIMITADA: nunca bucle infinito */
5:
    ldr     w17, [x16, #SPRD_STS1]
    tst     w17, #TX_FIFO_CNT_MASK
    b.eq    11f                             /* TX vacia -> escribir */
    subs    x9, x9, #1
    b.ne    5b
11:
    str     w0, [x16, #SPRD_TXD]            /* si la UART no responde, se ignora */
    ret
    .size putc, .-putc

/* ------------------------------------------------------------------ */
/* print_str: x0 = puntero a cadena terminada en 0                     */
/* ------------------------------------------------------------------ */
    .type print_str, %function
print_str:
    mov     x2, x0
6:
    ldrb    w0, [x2], #1
    cbz     w0, 7f
    bl      putc
    b       6b
7:
    ret
    .size print_str, .-print_str

/* ------------------------------------------------------------------ */
/* print_hex64: imprime x19 como 16 dígitos hexadecimales              */
/* ------------------------------------------------------------------ */
    .type print_hex64, %function
print_hex64:
    mov     x3, #16
8:
    lsr     x4, x19, #60
    and     x4, x4, #0xF
    cmp     x4, #10
    b.lo    9f
    add     x4, x4, #('a' - 10)
    b       10f
9:
    add     x4, x4, #'0'
10:
    mov     x0, x4
    bl      putc
    lsl     x19, x19, #4
    subs    x3, x3, #1
    b.ne    8b
    ret
    .size print_hex64, .-print_hex64

    .ltorg

report_prefix:
    .asciz  "BL:"
hexchars:
    .ascii  "0123456789abcdef"
msg_banner:
    .asciz  "A03-BLOB-KERNEL-OK "
msg_pc:
    .asciz  "pc=0x"
msg_nl:
    .asciz  "\n"

    .size _start, .-_start
