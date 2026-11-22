/*
 * rd_loader.c — loader de fase 2: copia un blob embebido a RAM y salta a el.
 *
 * LK deja el kernel (con el payload al final) en memoria. El blob va justo
 * despues del loader. Lo copiamos a LOAD_DST, hacemos coherencia completa de
 * d-cache e i-cache, y devolvemos LOAD_DST al entry en assembly.
 *
 * El ramdisk queda 100% stock: LK solo descomprime el primer miembro gzip,
 * asi que la estrategia de multi-miembro no sirve en este bootloader.
 */

typedef unsigned long long u64;

#define LOAD_DST   0xA1000000ULL           /* por encima del initrd */
#define MAX_BLOB   0x02000000ULL           /* 32 MB maximo */
#define PROC_OFF   0x010623A0ULL           /* linux_proc_banner */

static void copy_blob(u64 src, u64 dst, u64 n)
{
    volatile unsigned char *s = (volatile unsigned char *)src;
    volatile unsigned char *d = (volatile unsigned char *)dst;
    for (u64 i = 0; i < n; i++)
        d[i] = s[i];
}

static void cache_ops(u64 dst, u64 n)
{
    u64 p = dst;
    u64 end = dst + n;

    __asm__ volatile("dsb sy" ::: "memory");
    while (p < end) {
        __asm__ volatile("dc civac, %0" :: "r"(p) : "memory");
        p += 64;
    }
    __asm__ volatile("dsb sy" ::: "memory");

    p = dst;
    while (p < end) {
        __asm__ volatile("ic ivau, %0" :: "r"(p) : "memory");
        p += 64;
    }
    __asm__ volatile("dsb sy" ::: "memory");
    __asm__ volatile("ic iallu" ::: "memory");   /* red de seguridad */
    __asm__ volatile("dsb sy\n\tisb sy" ::: "memory");
}

#ifndef SYNTHETIC
static void write_marker(u64 image_base, char stage)
{
    volatile char *pv = (volatile char *)(image_base + PROC_OFF);
    pv[0] = 'R';
    pv[1] = 'L';
    pv[2] = ':';
    pv[3] = stage;
    pv[4] = 0;
}
#else
/* En el kernel sintetico no hay Linux: 0x10623A0 caeria fuera del Image
 * y podria pisar el ramdisk o el DTB. Los marcadores se desactivan. */
#define write_marker(base, stage) ((void)0)
#endif

u64 rd_loader_main(u64 image_base, u64 fdt, u64 blob_src, u64 blob_len)
{
    (void)fdt;

    write_marker(image_base, '0');

    if (blob_len == 0 || blob_len > MAX_BLOB) {
        write_marker(image_base, '2');
        return 0;
    }
    write_marker(image_base, '1');

    copy_blob(blob_src, LOAD_DST, blob_len);
    write_marker(image_base, '3');

    cache_ops(LOAD_DST, blob_len);
    write_marker(image_base, '4');

    return LOAD_DST;
}
