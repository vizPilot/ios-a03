/*
 * blob_loader.S — loader de fase 2: copia un blob a RAM y salta a él.
 *
 * Entra desde code0 con MMU off. x0 = FDT cargado por LK.
 *
 * Hace:
 *   1. construir boot_args en 0x92000000 (idéntico a bootargs_loader.S);
 *   2. copiar el blob situado justo después de este payload (en el kernel
 *      Linux, cargado por LK) a BLOB_DST = 0x91000000;
 *   3. invalidar caché de instrucciones;
 *   4. saltar al blob con:
 *        x0 = &boot_args
 *        x1 = image_base del kernel Linux
 *        x2 = stext del kernel Linux (retorno)
 *        x22 = FDT
 *
 * El blob devuelve el control a stext con x0 = FDT, así que Android arranca
 * con normalidad y podemos leer /proc/version.
 *
 * Los dos .word 0xDEADBEEF se parchean en make_blob_loader.py con el offset
 * y la longitud del blob dentro del payload.
 */

    .arch armv8-a
    .text
    .globl _start
    .type _start, %function

    .equ PAYLOAD_VMA, 0x0169E810
    .equ STOCK_ENTRY, 0x01200000
    .equ DELTA,       (PAYLOAD_VMA - STOCK_ENTRY)

#ifndef BLOB_DST_ADDR
#define BLOB_DST_ADDR 0x91000000
#endif

    .equ BA_DST,      0x92000000
    .equ BLOB_DST,    BLOB_DST_ADDR
    .equ BA_WORDS,    144

_start:
    mov     x22, x0                         /* conservar FDT */
    adr     x23, _start
    movz    x24, #(PAYLOAD_VMA & 0xffff)
    movk    x24, #((PAYLOAD_VMA >> 16) & 0xffff), lsl #16
    sub     x24, x23, x24                   /* x24 = image_base */

    /* ---------- 1. construir boot_args ---------- */
    movz    x19, #(BA_DST & 0xffff)
    movk    x19, #((BA_DST >> 16) & 0xffff), lsl #16

    mov     x5, #BA_WORDS
    mov     x6, x19
2:
    str     xzr, [x6], #8
    subs    x5, x5, #1
    b.ne    2b

    mov     w5, #2                          /* Revision = Version = 2 */
    strh    w5, [x19, #0]
    strh    w5, [x19, #2]

    ldr     x5, =0xfffffff007004000         /* VM_KERNEL_LINK_ADDRESS */
    str     x5, [x19, #8]

    ldr     x5, =0x0000000080000000         /* physBase */
    str     x5, [x19, #16]

    ldr     x5, =0x00000000fffff000         /* memSize */
    str     x5, [x19, #24]
    str     x5, [x19, #1144]                /* memSizeActual */

    adr     x6, cmdline
    add     x7, x19, #108
3:
    ldrb    w8, [x6], #1
    strb    w8, [x7], #1
    cbnz    w8, 3b

    ldr     w5, [x22]                       /* magic FDT (LE) */
    ldr     w6, [x22, #4]                   /* totalsize (BE) */
    rev     w6, w6
    str     x22, [x19, #96]                 /* deviceTreeP */
    str     w6, [x19, #104]                 /* deviceTreeLength */

    /* ---------- 2. copiar blob a RAM ---------- */
    adr     x2, blob_off_word
    ldr     w25, [x2]                       /* offset del blob desde _start */
    add     x2, x23, x25                    /* x2 = origen */

    adr     x3, blob_len_word
    ldr     w26, [x3]                       /* longitud del blob */
    add     x27, x26, #7
    lsr     x27, x27, #3                    /* nº de bloques de 8 bytes */

    movz    x3, #(BLOB_DST & 0xffff)
    movk    x3, #((BLOB_DST >> 16) & 0xffff), lsl #16

4:
    ldr     x28, [x2], #8
    str     x28, [x3], #8
    subs    x27, x27, #1
    b.ne    4b

    /* ---------- 3. coherencia d-cache / i-cache ---------- */
#ifndef SKIP_CACHE_OPS
    /* Limpiar el destino desde d-cache antes de invalidar i-cache.
       Sin MMU la memoria es Device, pero esto evita código obsoleto. */
    movz    x2, #(BLOB_DST & 0xffff)
    movk    x2, #((BLOB_DST >> 16) & 0xffff), lsl #16
    add     x27, x26, #63
    lsr     x27, x27, #6                    /* nº de líneas de 64 bytes */
9:
    dc      civac, x2
    add     x2, x2, #64
    subs    x27, x27, #1
    b.ne    9b
    dsb     sy
    ic      iallu
    dsb     sy
    isb     sy
#endif

    /* ---------- 4. saltar al blob copiado ---------- */
    mov     x0, x19                         /* x0 = &boot_args */
    mov     x1, x24                         /* x1 = image_base Linux */

    movz    x2, #(STOCK_ENTRY & 0xffff)     /* x2 = image_base + stext */
    movk    x2, #((STOCK_ENTRY >> 16) & 0xffff), lsl #16
    add     x2, x24, x2

    movz    x3, #(BLOB_DST & 0xffff)
    movk    x3, #((BLOB_DST >> 16) & 0xffff), lsl #16
    br      x3

    .ltorg

cmdline:
    .asciz  "debug=0x8 kext-dev-mode=1"

    .balign 8
blob_off_word:
    .word   0xDEADBEEF                      /* parcheado por make_blob_loader.py */
blob_len_word:
    .word   0xDEADBEEF                      /* parcheado por make_blob_loader.py */

    .size _start, .-_start
