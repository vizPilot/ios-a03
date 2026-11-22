/*
 * blob_kernel_min.S — blob de diagnóstico mínimo.
 *
 * No toca /proc/version ni la UART. Solo vuelve al kernel stock:
 *   x0 = FDT
 *   br x21 (stext)
 *
 * Se usa con el MISMO blob_loader que kernel-blob-loader2, para aislar si el
 * cuelgue está en el cuerpo del blob o en la copia/salto a RAM.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

_start:
    mov     x0, x22                         /* restaurar FDT */
    br      x2                              /* x2 = stext, pasado por el loader */

    .size _start, .-_start
