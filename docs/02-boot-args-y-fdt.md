# 02 — `boot_args` y el FDT

## Contrato de arranque verificado

Fuente: `pexpert/pexpert/arm64/boot.h` y `osfmk/arm64/start.s` en `xnu-10063.141.1`.

`_start` **no** recibe un puntero al FDT en `x0`. Recibe un puntero a `struct boot_args`:

```c
typedef struct boot_args {
    uint16_t Revision;
    uint16_t Version;
    uint64_t virtBase;
    uint64_t physBase;
    uint64_t memSize;
    uint64_t topOfKernelData;
    Boot_Video Video;              // 6 × uint64_t
    uint32_t machineType;
    void *deviceTreeP;             // <- FDT binario
    uint32_t deviceTreeLength;
    char CommandLine[1024];
    uint64_t bootFlags;
    uint64_t memSizeActual;
} boot_args;
```

Estado esperado al entrar:

- CPU en **EL1**.
- **MMU desactivada** (`start_first_cpu` instala sus propias page tables).
- Interrupts enmascarados.
- Kernelcache Mach-O ya cargado en RAM.
- `x0` = dirección física de `boot_args`.

No saltar desde Linux con MMU activa; hacer un trampolín que restaure ese estado.

## Offsets esperados en LP64

Verificar con `offsetof()` en la toolchain real:

| Campo | Offset | Tamaño |
|---|---:|---:|
| `Revision` | 0 | 2 |
| `Version` | 2 | 2 |
| padding | 4 | 4 |
| `virtBase` | 8 | 8 |
| `physBase` | 16 | 8 |
| `memSize` | 24 | 8 |
| `topOfKernelData` | 32 | 8 |
| `Video` | 40 | 48 |
| `machineType` | 88 | 4 |
| padding | 92 | 4 |
| `deviceTreeP` | 96 | 8 |
| `deviceTreeLength` | 104 | 4 |
| `CommandLine` | 108 | 1024 |
| padding | 1132 | 4 |
| `bootFlags` | 1136 | 8 |
| `memSizeActual` | 1144 | 8 |
| **total** | | **1152** |

## Valores que ya salen del DTB

```c
boot_args.physBase         = 0x80000000;
boot_args.memSize          = 0xFFFFF000;   // 0xfffff000 del nodo memory
boot_args.deviceTreeP      = <dirección física donde copiemos a03.dtb>;
boot_args.deviceTreeLength = 376049;       // totalsize, incluye padding cero
boot_args.bootFlags        = 0;            // inicialmente
```

Valores que **no** están en el DTB y hay que calcular/investigar:

| Campo | Origen |
|---|---|
| `virtBase` | `VM_KERNEL_LINK_ADDRESS` del kernelcache Mach-O compilado |
| `topOfKernelData` | fin de los datos del kernel en RAM |
| `machineType` | valor del lado Apple/iBoot; no inventar |
| `CommandLine` | command line de XNU, no la cadena Android de `chosen.bootargs` |
| `Video` | 0 al inicio; luego framebuffer `0xFD380000` |
| `Revision` / `Version` | usar los defines `kBootArgsRevision2` / `kBootArgsVersion2` del header |

## DTS vs DTB vs FDT

| Nombre | Qué es |
|---|---|
| `.dts` | texto legible (`D:\a03\a03.dts`) |
| `.dtb` / FDT | binario que consume el kernel (`D:\a03\a03.dtb`) |
| `boot_args.deviceTreeP` | dirección de ese binario |

El DTB entregado tiene 76.573 bytes de padding cero después del bloque de strings. No recortar: pasar el `totalsize` completo.

Regeneración opcional:

```bash
dtc -I dts -O dtb -o a03.dtb a03.dts
dtc -I dtb -O dts -o a03.roundtrip.dts a03.dtb
```

Mejor aún: conservar el `.dtb` original del firmware.

## Zonas de RAM a evitar

Según `chosen` y `reserved-memory`:

```text
0x80000000              inicio de RAM
0xA0000000..0xA00B5E49  initrd de Linux
0xFD380000              framebuffer reservado
```

Colocar kernelcache, DTB y `boot_args` fuera de esas zonas.
