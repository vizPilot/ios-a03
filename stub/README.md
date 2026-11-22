# stub/uart_hello — payload de fase 0

Payload mínimo para validar el punto de salto antes de meter `boot_args` o XNU.

## Qué imprime

```text
XNU-STUB-OK
EL=1
X0=0x0000000000000000
```

- `EL` se lee de `CurrentEL`.
- `X0` es el valor con el que se llamó al stub. En esta fase debe ser `0`.
- Sale por `serial1` del DTB: `0x200b0000`, 115200 8N1.

## Supuestos

- La CPU está en EL1, con MMU desactivada e interrupts enmascarados.
- El payload se salta desde el initramfs de un `boot.img` propio.
- La UART ya tiene clocks habilitados por LK/Linux; además el stub los reconfigura:
  - divisor `26000000 / 115200 = 225` en `CLKD0/CLKD1`,
  - `LCR = 0x1C` (8N1),
  - `IEN = 0`, `CTL1 = 0`.

Los offsets vienen del driver real `sprd_serial.c` del kernel del A03.

## Compilación

```bash
cd stub
make
```

Si no tienes el cross compiler de GNU:

```bash
make CC="clang --target=aarch64-linux-gnu" OBJCOPY="llvm-objcopy"
```

La dirección de carga por defecto es `0x91000000`. Cambiar si colisiona con el kernel o el initrd:

```bash
make clean
# editar link.ld o pasar BASE soportándolo en el script
```

## Huella por framebuffer (cuando no hay serial)

El payload escribe dos buffers **antes** de tocar la UART:

| Buffer | Dirección | Valor escrito |
|---|---|---|
| `logobuffer@9e000000` (`lcd_base` del bootargs) | `0x9E000000` | blanco (`0xFF`) |
| `framebuffer-mem@fd380000` | `0xFD380000` | negro (`0x00`) |

Tamaño: `0x465000` bytes = `1600 * 720 * 4`, cubre RGB24 y RGBA32.

Interpretación en pantalla:

| Resultado | Conclusión |
|---|---|
| Pantalla blanca | El payload corrió; el buffer vivo es `0x9E000000` |
| Pantalla negra | El payload corrió; el buffer vivo es `0xFD380000` |
| Sin cambio | O no se ejecutó (firma/offset), o LK apagó el display antes de saltar |

Además, la UART **ya no se reinicializa por defecto** (`UART_REINIT=0`). El divisor `26000000/115200 = 225` solo es válido si el clock real es 26 MHz; si no, la salida serial muere. Para forzar el viejo comportamiento:

```bash
make clean
make UART_REINIT=1
```

## Arrancar como kernel (caso fastbootd)

`fastbootd` es el fastboot de Android en userspace; **no soporta `fastboot boot`**. Ese comando solo existe en el fastboot de LK (`adb reboot bootloader`).

Para arrancar el payload **como kernel**, reemplaza el kernel del `boot.img` por `kernel.img`:

```powershell
cd D:\ios-a03\stub
make
.\make_kernel_image.ps1
```

`kernel.img` queda así:

```text
0x00000  cabecera ARM64 Image (magic "ARMd", text_offset = 0x80000)
         code0 = B 0x80000   → si LK salta a kernel_addr
0x80000  uart_hello.bin      → si LK salta a kernel_addr + 0x80000
```

Así funciona con cualquiera de las dos convenciones de LK sin saber cu usa.

Pasos:

1. Extraer el `boot.img` stock:
   ```bash
   unpack_bootimg --boot_img boot.img --out stock
   ```
2. Anotar los valores que imprime: `base`, `kernel_addr`, `ramdisk_addr`, `pagesize`, `cmdline`, `dtb`.
3. Reconstruir con `mkbootimg`, reutilizando esos valores pero con `--kernel kernel.img`.
4. Arrancar con `fastboot boot new-boot.img` desde **bootloader fastboot**, o con Odin usando un `tar.md5` que contenga solo `boot.img`.

## Integración alternativa con initramfs

Si luego quieres el trampolín desde userspace:

1. Copiar `uart_hello.bin` al initramfs, por ejemplo `/xnu/uart_hello.bin`.
2. En un proceso early, copiarlo a `0x91000000`.
3. Saltar con `x0 = 0`.

```asm
msr     daifset, #0xF        // enmascarar interrupts
/* si CurrentEL == 2: preparar SPSR_EL2/ELR_EL2 y eret a EL1 */
mov     x0, #0               // todavía sin boot_args
br      x1                   // x1 = 0x91000000
```

## Qué valida este payload

| Si ves... | Significa |
|---|---|
| `XNU-STUB-OK` | UART y offsets correctos |
| `EL=1` | El trampolín bajó bien de EL2 si hacía falta |
| `X0=0x0000000000000000` | El salto preservó el argumento |

Si no sale nada, revisa primero que la consola del `boot.img` esté en `serial1` (`0x200b0000`) y no en `serial0` (`0x200a0000`).

## Siguiente paso

Reemplazar el banner por validación de `boot_args`:

```text
x0 -> boot_args.deviceTreeP
      boot_args.deviceTreeLength == 376049
```

Recién después saltar a `_start` de XNU.
