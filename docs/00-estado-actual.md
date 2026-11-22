# 00 — Estado actual

## DTB del A03

Archivo analizado: `D:\a03\a03.dtb` (376.049 bytes).

| Campo FDT | Valor |
|---|---|
| Magic | `0xD00DFEED` |
| `totalsize` | `376049` |
| Tamaño real del archivo | `376049` ✅ |
| `off_dt_struct` | `56` |
| `size_dt_struct` | `271636` |
| `off_dt_strings` | `271692` |
| `size_dt_strings` | `27784` |
| `version` | `17` |
| `last_comp_version` | `16` |
| `boot_cpuid_phys` | `0` |

El bloque de strings termina en `271692 + 27784 = 299476`. El resto hasta `376049` son **76.573 bytes de padding cero**. Es normal en imágenes embebidas; `deviceTreeLength` debe ser `376049` (`totalsize`).

El `.dts` adjunto (`D:\a03\a03.dts`) es la representación descompilada del mismo FDT. Contiene `phandle = <0x...>`, cadenas con `\0` y `androidboot.*`, lo que confirma que viene de un DTB.

## Datos útiles extraídos

| Dato | Valor |
|---|---|
| `compatible` root | `sprd,ums9230` |
| `model` | `Spreadtrum UMS9230 1H10 SoC` |
| `cpuinfo_hardware` | `UNISOC T606` |
| RAM | `memory@80000000`, `reg = <0 0x80000000 0 0xfffff000>` |
| `memSize` deducido | `0xFFFFF000` ≈ 4 GiB |
| CPUs | 6× `arm,cortex-a55` + 2× `arm,cortex-a75` |
| `enable-method` | `psci` |
| PSCI | `arm,psci-0.2`, `method = "smc"` |
| GIC | `interrupt-controller@10000000`, `arm,gic-v3` |
| Redistribuidores GIC | base `0x10040000`, stride `0x20000` |
| Timer | `arm,armv8-timer`, PPIs `13,14,11,10` |
| UART 0 | `serial@0x200a0000`, alias `serial0` |
| UART 1 | `serial@0x200b0000`, alias `serial1` |
| UART 2 | `serial@0x200c0000`, alias `serial2` |
| Consola | `stdout-path = "serial1:115200n8"` → **UART en `0x200b0000`** |
| Initrd Linux | `0xA0000000..0xA00B5E49` (zona a evitar) |
| Framebuffer reservado | `framebuffer-mem@0xFD380000` |

## Estado del bootloader

Cadena: **BootROM → SPL (U-Boot) → LK → Linux**.

Resultados reales de fastboot:

```text
fastboot getvar unlocked      → unlocked: yes
fastboot getvar secure        → secure: yes
fastboot getvar verified      → FAILED (Unknown variable)
fastboot getvar is-unlocked   → FAILED (Unknown variable)
```

Interpretación:

- `unlocked: yes` confirma AVB/Verified Boot desactivado.
- `verified` e `is-unlocked` simplemente **no están implementados** por este LK; no indican problema.
- `secure: yes` es ambiguo: en algunos LK de vendors significa que la verificación de firmware/eFuse sigue activa aunque AVB esté desbloqueado. **No se puede asumir** que un `boot.img` propio será aceptado.

Prueba no destructiva pendiente:

1. Repack de un `boot.img` stock sin cambiar contenido → `fastboot boot boot.img`.
2. Repack con el contenido modificado (firma inválida) → `fastboot boot boot.img`.

Si el segundo arranca, la ruta elegida funciona. Si devuelve error de seguridad, hay que replantear el punto de inyección.

## Privacidad

El DTS/DTB contiene `serial-number` y `androidboot.serialno`. No publicar el archivo sin sanitizar esos valores.
