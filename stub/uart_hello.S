/*
 * uart_hello.S — payload de fase 0 para el bring-up de XNU en A03
 *
 * Imprime por la UART de consola del DTB:
 *   serial1 = /soc/ap-apb/serial@0x200b0000, 115200 8N1
 *
 * Contrato temporal:
 *   x0 = 0 en esta fase (todavía no hay boot_args)
 *   CPU en EL1, MMU off, interrupts enmascarados
 *
 * Registros y divisor tomados de:
 *   drivers/tty/serial/sprd_serial.c
 *   del repo IverCoder/android_kernel_samsung_a03
 */

#ifndef UART_REINIT
#define UART_REINIT 0
#endif

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

/* Base de la UART de consola (alias serial1 del DTB) */
    .equ UART_BASE,      0x200b0000

/* Offsets del driver SPRD UART */
    .equ SPRD_TXD,       0x0000
    .equ SPRD_STS1,      0x000C
    .equ SPRD_IEN,       0x0010
    .equ SPRD_LCR,       0x0018
    .equ SPRD_CTL1,      0x001C
    .equ SPRD_CLKD0,     0x0024
    .equ SPRD_CLKD1,     0x0028

/* SPRD_STS1: TX FIFO count = bits 15:8; 0 significa TX vacía */
    .equ TX_FIFO_CNT_MASK, 0xFF00

/* 26 MHz / 115200 = 225 (0xE1) */
    .equ UART_CLK_HZ,    26000000
    .equ UART_BAUD,      115200
    .equ UART_DIV,       (UART_CLK_HZ / UART_BAUD)

/* 8N1: data len 8 (0xC) | 1 stop bit (0x10) */
    .equ LCR_8N1,        0x1C

/* Buffers de display del DTB. Cubrimos 1600*720*4 bytes para
   funcionar tanto con RGB24 como con RGBA32. */
    .equ FB_LOGO_BASE,   0x9E000000   /* logobuffer@9e000000 (bootargs lcd_base) */
    .equ FB_KERNEL_BASE, 0xFD380000   /* framebuffer-mem@fd380000 */
    .equ FB_BYTES,       0x465000     /* 1600 * 720 * 4 */
    .equ FB_CHUNKS,      (FB_BYTES / 16)

/* Marcador de ejecución dentro de sec_dbg@0x8F000000 (0x1FF000).
   Sobrevive al reinicio y se lee desde Android con root. */
    .equ MARKER_BASE,    0x8F000000

/* Zona ramoops completa: 0xFFF80000..0xFFFC0000 (8 bloques de 0x8000).
   Escribimos la cabecera en TODOS los bloques para garantizar que
   pstore encuentre el mensaje sin importar el layout real.
   struct persistent_ram_buffer { sig, start, size, data[] }
   sig = 0x43474244 ("DBGC" = PERSISTENT_RAM_SIG). */
    .equ RAMOOPS_BASE,      0xFFF80000
    .equ RAMOOPS_BLOCKS,    8
    .equ RAMOOPS_BLOCK_SZ,  0x8000

/* sprd imem: restart_reason@0x7E0, upload_cause@0x7E4 */
    .equ IMEM_RESTART_REASON, 0x7E0
    .equ IMEM_UPLOAD_CAUSE,   0x7E4

/* ------------------------------------------------------------------ */
/* putc: imprime el byte bajo de x0                                    */
/* Clobbers: x0, x16, x17                                              */
/* ------------------------------------------------------------------ */
    .type putc, %function
putc:
    ldr     x16, =UART_BASE
1:
    ldr     w17, [x16, #SPRD_STS1]
    tst     w17, #TX_FIFO_CNT_MASK
    b.ne    1b
    str     w0, [x16, #SPRD_TXD]
    ret
    .size putc, .-putc

/* ------------------------------------------------------------------ */
/* print_str: x0 = puntero a cadena terminada en 0                     */
/* Clobbers: x0, x2, x16, x17                                          */
/* ------------------------------------------------------------------ */
    .type print_str, %function
print_str:
    mov     x2, x0
1:
    ldrb    w0, [x2], #1
    cbz     w0, 2f
    bl      putc
    b       1b
2:
    ret
    .size print_str, .-print_str

/* ------------------------------------------------------------------ */
/* print_hex64: imprime x19 como 16 dígitos hexadecimales              */
/* Clobbers: x0, x3, x4, x16, x17, x19                                 */
/* ------------------------------------------------------------------ */
    .type print_hex64, %function
print_hex64:
    mov     x3, #16
1:
    lsr     x4, x19, #60
    and     x4, x4, #0xF
    cmp     x4, #10
    b.lo    2f
    add     x4, x4, #('a' - 10)
    b       3f
2:
    add     x4, x4, #'0'
3:
    mov     x0, x4
    bl      putc
    lsl     x19, x19, #4
    subs    x3, x3, #1
    b.ne    1b
    ret
    .size print_hex64, .-print_hex64

/* ------------------------------------------------------------------ */
/* uart_init: reconfigura la UART a 115200 8N1, sin IRQ/DMA/loopback   */
/* Clobbers: x16, x17                                                  */
/* ------------------------------------------------------------------ */
    .type uart_init, %function
uart_init:
    ldr     x16, =UART_BASE

    /* deshabilitar interrupciones del UART */
    str     wzr, [x16, #SPRD_IEN]

    /* divisor de baud: CLKD0 = bits 0..15, CLKD1 = bits 16..20 */
    mov     w17, #UART_DIV
    str     w17, [x16, #SPRD_CLKD0]
    str     wzr, [x16, #SPRD_CLKD1]

    /* 8N1 */
    mov     w17, #LCR_8N1
    str     w17, [x16, #SPRD_LCR]

    /* sin DMA, sin loopback, sin control de flujo por hardware */
    str     wzr, [x16, #SPRD_CTL1]
    ret
    .size uart_init, .-uart_init

/* ------------------------------------------------------------------ */
/* fill_region: rellena FB_BYTES desde x0 con el patrón de x1           */
/* Clobbers: x0, x1, x2, x3                                            */
/* ------------------------------------------------------------------ */
    .type fill_region, %function
fill_region:
    mov     x3, x1
    ldr     x2, =FB_CHUNKS
1:
    stp     x3, x3, [x0], #16
    subs    x2, x2, #1
    b.ne    1b
    ret
    .size fill_region, .-fill_region

/* ------------------------------------------------------------------ */
/* _start                                                              */
/* ------------------------------------------------------------------ */
_start:
    /* x0 puede ser 0 en esta fase; lo guardamos para imprimirlo */
    mov     x19, x0
    mov     x21, x0

    /* Marcador de ejecución: se lee después desde Android con root. */
    ldr     x0, =MARKER_BASE
    movz    w1, #0x5542
    movk    w1, #0x5853, lsl #16     /* "XSUB" = 0x58535542 */
    str     w1, [x0, #0x00]
    mrs     x20, CurrentEL
    lsr     x20, x20, #2
    and     x20, x20, #0x3
    str     w20, [x0, #0x04]
    str     w21, [x0, #0x08]
    lsr     x21, x21, #32
    str     w21, [x0, #0x0C]
    movz    w2, #0xB001
    movk    w2, #0xA03F, lsl #16     /* 0xA03FB001 */
    str     w2, [x0, #0x10]

    /* sprd imem: restart_reason y upload_cause sobreviven al reinicio. */
    ldr     x0, =IMEM_RESTART_REASON
    movz    w1, #0xB001
    movk    w1, #0xA03F, lsl #16     /* 0xA03FB001 */
    str     w1, [x0]
    ldr     x0, =IMEM_UPLOAD_CAUSE
    movz    w1, #0x5542
    movk    w1, #0x5853, lsl #16     /* "XSUB" */
    str     w1, [x0]

    /* Marcador en TODOS los bloques ramoops (8 x 0x8000):
       garantiza que pstore lea el mensaje sin importar el layout real. */
    ldr     x6, =RAMOOPS_BASE
    mov     w7, #RAMOOPS_BLOCKS
2:
    movz    w1, #0x4244
    movk    w1, #0x4347, lsl #16     /* 0x43474244 = "DBGC" */
    str     w1, [x6, #0x00]          /* sig */
    str     wzr, [x6, #0x04]         /* start = 0 */
    mov     w1, #19                  /* 19 bytes de mensaje */
    str     w1, [x6, #0x08]          /* size */
    add     x2, x6, #12             /* x2 = &buffer->data */
    adr     x1, pstore_msg
    mov     w4, #19
3:
    ldrb    w3, [x1], #1
    strb    w3, [x2], #1
    subs    w4, w4, #1
    b.ne    3b
    add     w3, w20, #'0'            /* EL real en el byte 17 de data */
    strb    w3, [x6, #(12 + 17)]     /* "EL=0" -> "EL=<n>" */
    add     x6, x6, #RAMOOPS_BLOCK_SZ
    subs    w7, w7, #1
    b.ne    2b

    /* Huella visual primero: no depende de clocks de UART.
       Logo buffer en blanco, framebuffer de kernel en negro. */
    ldr     x0, =FB_LOGO_BASE
    mvn     x1, xzr                 /* bytes 0xFF */
    bl      fill_region

    ldr     x0, =FB_KERNEL_BASE
    mov     x1, #0                  /* bytes 0x00 */
    bl      fill_region

#if UART_REINIT
    /* Desactivado por defecto: confiamos en la UART ya configurada por LK.
       Activar solo si el clock real del UART es 26 MHz. */
    bl      uart_init
#endif

    adr     x0, msg_banner
    bl      print_str

    adr     x0, msg_el
    bl      print_str
    mrs     x20, CurrentEL
    lsr     x20, x20, #2
    and     x20, x20, #0x3
    add     x0, x20, #'0'
    bl      putc
    adr     x0, msg_nl
    bl      print_str

    adr     x0, msg_x0
    bl      print_str
    bl      print_hex64
    adr     x0, msg_nl
    bl      print_str

hang:
    wfe
    b       hang
    .size _start, .-_start

    .ltorg

    .section .rodata
pstore_msg: .asciz "XSUB A03FB001 EL=0\n"   /* 19 bytes sin el NUL; el EL se rellena arriba */

msg_banner: .asciz "XNU-STUB-PROBE\n"
msg_el:     .asciz "EL="
msg_x0:     .asciz "X0=0x"
msg_nl:     .asciz "\n"

    .end
