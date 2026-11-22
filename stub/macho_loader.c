/*
 * macho_loader.c — cargador estilo iBoot para un kernelcache Mach-O arm64.
 *
 * Recibe el Mach-O embebido en el payload, carga cada LC_SEGMENT_64 a RAM,
 * construye boot_args (layout de docs/02) y devuelve la direccion fisica
 * del entry. El entry en assembly pone x0 = &boot_args y salta.
 *
 * MMU off, sin stack, sin libc. Direcciones fisicas.
 *
 * Asignacion: __TEXT (vmaddr = link base) -> KERN_PHYS.
 * El resto de segmentos se rebasan: dst = KERN_PHYS + (vmaddr - link_base).
 * Esto es un cargador de investigacion: con un XNU real habra que revisar
 * como physBase/virtBase fijan el mapa virtual<->fisico en start.s.
 */

typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;

#define BOOTARGS_PA    0x92000000ULL
#define DTB_DST        0x92001000ULL
#define KERN_PHYS      0xA2000000ULL
#define DEFAULT_VBASE  0xFFFFFFF007004000ULL
#define MAX_KERN_SIZE  0x04000000ULL        /* 64 MB */

#define MH_MAGIC_64    0xfeedfacfu
#define LC_SEGMENT_64  0x19u
#define LC_UNIXTHREAD  0x05u
#define LC_MAIN        0x80000028u
#define ARM_THREAD_STATE64 6u

#define O_REVISION        0
#define O_VERSION         2
#define O_VIRTBASE        8
#define O_PHYSBASE        16
#define O_MEMSIZE         24
#define O_TOPOFDATA       32
#define O_DTP             96
#define O_DTLEN           104
#define O_CMDLINE         108
#define O_BOOTFLAGS       1136
#define O_MEMSIZEACTUAL   1144

static u32 rd32(const volatile u8 *p)
{
    return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24);
}

static u64 rd64(const volatile u8 *p)
{
    return (u64)rd32(p) | ((u64)rd32(p + 4) << 32);
}

static int segname_is(const volatile u8 *p, const char *s)
{
    for (u32 i = 0; i < 16; i++) {
        if (p[i] != (u8)s[i])
            return 0;
        if (p[i] == 0)
            break;
    }
    return 1;
}

static void copy_bytes(u64 src, u64 dst, u64 n)
{
    const volatile u8 *s = (const volatile u8 *)src;
    volatile u8 *d = (volatile u8 *)dst;
    for (u64 i = 0; i < n; i++)
        d[i] = s[i];
}

static void zero_bytes(u64 dst, u64 n)
{
    volatile u8 *d = (volatile u8 *)dst;
    for (u64 i = 0; i < n; i++)
        d[i] = 0;
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

static void put16(u64 off, u16 v) { *(volatile u16 *)(BOOTARGS_PA + off) = v; }
static void put32(u64 off, u32 v) { *(volatile u32 *)(BOOTARGS_PA + off) = v; }
static void put64(u64 off, u64 v) { *(volatile u64 *)(BOOTARGS_PA + off) = v; }

static void set_cmdline(void)
{
    static const char cmd[] = "debug=0x8 kext-dev-mode=1";
    volatile char *dst = (volatile char *)(BOOTARGS_PA + O_CMDLINE);
    for (u64 i = 0; i < sizeof(cmd); i++)
        dst[i] = cmd[i];
}

/* Itera los load commands. FIND y LOAD se definen como macros para no
 * necesitar punteros a funcion (evita stack y .got). */
#define FOR_EACH_CMD(BODY)                                                    \
    do {                                                                      \
        u64 _off = 0;                                                         \
        while (_off + 8 <= sizeofcmds) {                                      \
            const volatile u8 *_c = m + 32 + _off;                            \
            u32 _cmd = rd32(_c);                                              \
            u32 _sz  = rd32(_c + 4);                                          \
            if (_sz < 8 || _off + _sz > sizeofcmds)                           \
                break;                                                        \
            { BODY }                                                          \
            _off += _sz;                                                      \
        }                                                                     \
    } while (0)

u64 macho_main(u64 image_base, u64 macho_src, u64 macho_len,
               u64 dtb_src, u64 dtb_len)
{
    (void)image_base;

    /* 1. DTB crudo */
    copy_bytes(dtb_src, DTB_DST, dtb_len);
    cache_ops(DTB_DST, dtb_len);

    /* 2. Cabecera Mach-O */
    const volatile u8 *m = (const volatile u8 *)macho_src;
    if (macho_len < 32 || rd32(m) != MH_MAGIC_64)
        return 0;

    u32 ncmds = rd32(m + 16);
    u32 sizeofcmds = rd32(m + 20);
    if (ncmds == 0 || sizeofcmds > macho_len - 32)
        return 0;

    u64 link_base = DEFAULT_VBASE;
    u64 entry_virt = 0;
    u64 entry_off = 0;

    /* 3. Primera pasada: link base y entry */
#define FIND_BODY                                                             \
    if (_cmd == LC_SEGMENT_64 && _sz >= 72 && segname_is(_c + 8, "__TEXT"))   \
        link_base = rd64(_c + 24);                                            \
    if (_cmd == LC_UNIXTHREAD && _sz >= 288 && rd32(_c + 8) == ARM_THREAD_STATE64) \
        entry_virt = rd64(_c + 272);                                          \
    if (_cmd == LC_MAIN && _sz >= 16)                                         \
        entry_off = rd64(_c + 8);
    FOR_EACH_CMD(FIND_BODY);
#undef FIND_BODY

    /* 4. Segunda pasada: cargar segmentos */
    u64 top = KERN_PHYS;
#define LOAD_BODY                                                             \
    if (_cmd == LC_SEGMENT_64 && _sz >= 72) {                                 \
        u64 vmaddr   = rd64(_c + 24);                                         \
        u64 vmsize   = rd64(_c + 32);                                         \
        u64 fileoff  = rd64(_c + 40);                                         \
        u64 filesize = rd64(_c + 48);                                         \
        if (vmsize == 0 || vmsize > MAX_KERN_SIZE)                            \
            return 0;                                                         \
        if (vmaddr < link_base)                                               \
            return 0;                                                         \
        if (fileoff > macho_len || filesize > macho_len - fileoff)            \
            return 0;                                                         \
        u64 dst = KERN_PHYS + (vmaddr - link_base);                           \
        if (dst < KERN_PHYS || dst >= KERN_PHYS + MAX_KERN_SIZE)              \
            return 0;                                                         \
        copy_bytes(macho_src + fileoff, dst, filesize);                       \
        if (vmsize > filesize)                                                \
            zero_bytes(dst + filesize, vmsize - filesize);                    \
        cache_ops(dst, vmsize);                                               \
        if (dst + vmsize > top)                                               \
            top = dst + vmsize;                                               \
    }
    FOR_EACH_CMD(LOAD_BODY);
#undef LOAD_BODY

    /* 5. Entry fisico */
    u64 entry_phys;
    if (entry_virt) {
        if (entry_virt < link_base)
            return 0;
        entry_phys = KERN_PHYS + (entry_virt - link_base);
    } else if (entry_off) {
        entry_phys = KERN_PHYS + entry_off;
    } else {
        entry_phys = KERN_PHYS;
    }

    /* 6. boot_args */
    volatile u8 *ba = (volatile u8 *)BOOTARGS_PA;
    for (u64 i = 0; i < 1152; i++)
        ba[i] = 0;

    put16(O_REVISION, 2);
    put16(O_VERSION, 2);
    put64(O_VIRTBASE, link_base);
    put64(O_PHYSBASE, 0x80000000ULL);
    put64(O_MEMSIZE,  0xFFFFF000ULL);
    put64(O_TOPOFDATA, top);
    put64(O_DTP,      DTB_DST);
    put32(O_DTLEN,    (u32)dtb_len);
    set_cmdline();
    put64(O_BOOTFLAGS, 0);
    put64(O_MEMSIZEACTUAL, 0xFFFFF000ULL);
    cache_ops(BOOTARGS_PA, 1152);

    return entry_phys;
}
