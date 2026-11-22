/*
 * xnu_handoff_loader.c — construye boot_args y prepara el salto estilo _start.
 *
 * En el kernel sintetico no hay Linux: aqui tenemos que crear nosotros la
 * estructura que antes nos daba el kernel. layout verificado en docs/02:
 *
 *   0   Revision u16 = 2
 *   2   Version  u16 = 2
 *   8   virtBase      = 0xfffffff007004000
 *   16  physBase      = 0x80000000
 *   24  memSize       = 0xfffff000
 *   32  topOfKernelData (0, desconocido)
 *   40  Video[48]     = 0
 *   88  machineType   = 0 (no inventar)
 *   96  deviceTreeP   = DTB_DST
 *   104 deviceTreeLength u32 = 376049
 *   108 CommandLine[1024]
 *   1136 bootFlags    = 0
 *   1144 memSizeActual = 0xfffff000
 *   total 1152
 *
 * El DTB crudo (D:\a03\a03.dtb) va embebido en el payload y se copia a DTB_DST.
 * MMU off: todas las direcciones son fisicas.
 */

typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;

#define BOOTARGS_PA 0x92000000ULL
#define DTB_DST     0x92001000ULL
#define BLOB_DST    0xA1000000ULL
#define BA_SIZE     1152ULL

#define O_REVISION        0
#define O_VERSION         2
#define O_VIRTBASE        8
#define O_PHYSBASE        16
#define O_MEMSIZE         24
#define O_DTP             96
#define O_DTLEN           104
#define O_CMDLINE         108
#define O_BOOTFLAGS       1136
#define O_MEMSIZEACTUAL   1144

static void copy_bytes(u64 src, u64 dst, u64 n)
{
    const volatile unsigned char *s = (const volatile unsigned char *)src;
    volatile unsigned char *d = (volatile unsigned char *)dst;
    for (u64 i = 0; i < n; i++)
        d[i] = s[i];
}

static void cache_ops(u64 start, u64 n)
{
    u64 p = start;
    u64 end = start + n;

    __asm__ volatile("dsb sy" ::: "memory");
    while (p < end) {
        __asm__ volatile("dc civac, %0" :: "r"(p) : "memory");
        p += 64;
    }
    __asm__ volatile("dsb sy" ::: "memory");

    p = start;
    while (p < end) {
        __asm__ volatile("ic ivau, %0" :: "r"(p) : "memory");
        p += 64;
    }
    __asm__ volatile("dsb sy" ::: "memory");
    __asm__ volatile("ic iallu" ::: "memory");
    __asm__ volatile("dsb sy\n\tisb sy" ::: "memory");
}

static void put16(u64 off, u16 v)   { *(volatile u16 *)(BOOTARGS_PA + off) = v; }
static void put32(u64 off, u32 v)   { *(volatile u32 *)(BOOTARGS_PA + off) = v; }
static void put64(u64 off, u64 v)   { *(volatile u64 *)(BOOTARGS_PA + off) = v; }

static void set_cmdline(void)
{
    static const char cmd[] = "debug=0x8 kext-dev-mode=1";
    volatile char *dst = (volatile char *)(BOOTARGS_PA + O_CMDLINE);
    for (u64 i = 0; i < sizeof(cmd); i++)
        dst[i] = cmd[i];
}

u64 handoff_main(u64 image_base, u64 blob_src, u64 blob_len,
                 u64 dtb_src, u64 dtb_len)
{
    (void)image_base;

    /* 1. DTB crudo -> direccion que pondremos en deviceTreeP */
    copy_bytes(dtb_src, DTB_DST, dtb_len);
    cache_ops(DTB_DST, dtb_len);

    /* 2. blob (futuro XNU) -> 0xA1000000 */
    copy_bytes(blob_src, BLOB_DST, blob_len);
    cache_ops(BLOB_DST, blob_len);

    /* 3. boot_args: cero y relleno */
    volatile unsigned char *ba = (volatile unsigned char *)BOOTARGS_PA;
    for (u64 i = 0; i < BA_SIZE; i++)
        ba[i] = 0;

    put16(O_REVISION, 2);
    put16(O_VERSION, 2);
    put64(O_VIRTBASE, 0xFFFFFFF007004000ULL);
    put64(O_PHYSBASE, 0x80000000ULL);
    put64(O_MEMSIZE,  0xFFFFF000ULL);
    put64(O_DTP,      DTB_DST);
    put32(O_DTLEN,    (u32)dtb_len);
    set_cmdline();
    put64(O_BOOTFLAGS, 0);
    put64(O_MEMSIZEACTUAL, 0xFFFFF000ULL);

    cache_ops(BOOTARGS_PA, BA_SIZE);

    return BLOB_DST;
}
