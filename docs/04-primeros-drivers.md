# 04 — Primeros drivers en XNU

## Orden de brings-up

| Fase | Entregable | Cómo verificarlo |
|---|---|---|
| 0 | Payload UART-only desde `boot.img` | `"XNU-STUB-OK\n"` en 115200 8N1 |
| 1 | Trampolín a EL1 con `boot_args` falso | Imprime `CurrentEL`, `x0`, `SCTLR_EL1` |
| 2 | XNU compilado en QEMU | Salida serial antes de tocar el A03 |
| 3 | XNU en A03 hasta `arm_init()` | Consola XNU inicial |
| 4 | Driver UART IOKit | `printf` de kernel por `0x200b0000` |
| 5 | Driver timer + GICv3 | Interrupts y `mach_absolute_time` |
| 6 | Framebuffer | `0xFD380000`, 1600×720 según bootargs |

No intentar fases 4-6 antes de tener la fase 2 estable en QEMU.

## UART

La consola del FDT es:

```text
stdout-path = "serial1:115200n8"
serial1 → /soc/ap-apb/serial@0x200b0000
```

Otros UARTs:

```text
serial0 → 0x200a0000
serial2 → 0x200c0000
```

Compatibilidad en el DTB:

```text
sprd,ums9230-uart
sprd,sc9836-uart
```

XNU no trae un driver que haga match con esos strings. Hay que crear un nub/driver IOKit propio, o un compatible propio y registrar el driver.

Checklist mínimo del driver:

1. `mmio_read/write` a `0x200b0000`.
2. Configurar clock (el DTB referencia `clocks = <0x02 0x0f 0x03 0x02 0x04>` para `serial1`).
3. Baud 115200, 8N1, sin FIFO compleja al inicio.
4. `polled_putc` antes de habilitar interrupts.

## Timer

```text
compatible = "arm,armv8-timer"
interrupts = PPIs 13, 14, 11, 10
```

El timer arquitectural ARMv8 es estándar, pero XNU espera sus propios drivers. Servirá para:

- `mach_absolute_time`,
- calendario de kernel,
- watchdog de early boot.

## GICv3

```text
interrupt-controller@10000000   compatible = "arm,gic-v3"
redistributor base 0x10040000   stride 0x20000
```

XNU de Apple usa su controlador de interrupciones propio, no GICv3. Necesitamos:

- driver IOKit para Distributor/Redistributors,
- manejo de PPIs/SPIs,
- `ipi` del nodo `/interrupt-controller`.

Hasta que exista, el kernel solo podrá funcionar con polling.

## PSCI

```text
psci { compatible = "arm,psci-0.2"; method = "smc"; }
```

Se usará para arrancar/detener CPUs secundarias. Verificar que el monitor (SPL/LK/TF-A) provee `PSCI_CPU_ON`, `PSCI_CPU_OFF` y `PSCI_SYSTEM_RESET`.

## Brecha de drivers

| Hardware en T606 | Driver en XNU de Apple | Acción |
|---|---|---|
| `sprd,ums9230-uart` | No | Escribir driver IOKit |
| `arm,gic-v3` | No (usa AIC) | Escribir driver IOKit |
| `arm,armv8-timer` | Parcial/propio | Adaptar |
| Clocks SPRD | No | Portar desde Linux `4.14.199` |
| Panel MIPI / framebuffer | No | Portar secuencias del DTS |

El kernel Linux de referencia `IverCoder/android_kernel_samsung_a03` sirve como **fuente de datos y algoritmos**, no como código copiable directamente a XNU.

## Límite final

Aunque UART, timer, GIC y framebuffer funcionen, **SpringBoard no arrancará**: no hay SEP, no hay keybags y el userland de Apple no se puede reutilizar. El resultado válido es una consola XNU propia, no iOS.
