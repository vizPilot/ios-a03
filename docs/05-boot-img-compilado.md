# 05 — `boot.img` compilado con WSL

## Entorno

```text
WSL: Ubuntu 24.04.5 LTS (x86_64)
aarch64-linux-gnu-gcc: /usr/bin/aarch64-linux-gnu-gcc
unpack_bootimg:        /usr/bin/unpack_bootimg
mkbootimg:             /usr/bin/mkbootimg
python3:               disponible
```

## Datos del `boot.img` stock

Archivo: `D:\a03\boot.img` (67.108.864 bytes).

```text
boot magic: ANDROID!
kernel_size: 23717904
kernel load address: 0x00008000
ramdisk size: 745033
ramdisk load address: 0x01000000
page size: 2048
os version: 11.0.0
os patch level: 2025-08
boot image header version: 2
product name: SRPUI23B009
command line args: console=ttyS1,115200n8
boot header size: 1660
dtb size: 179505
dtb address: 0x0000000001f00000
```

`base` se infiere como `0x0`, por lo que los offsets son iguales a las direcciones de carga.

## Build ejecutado

```bash
cd /mnt/d/ios-a03/stub
make
python3 make_kernel_image.py
```

Resultado:

```text
uart_hello.elf  67192 bytes   ELF 64-bit ARM aarch64
uart_hello.bin    257 bytes
kernel.img     524545 bytes  (0x80101)
```

Cabecera de `kernel.img`:

```text
00 00 02 14  -> code0 = B 0x80000
1f 20 03 d5  -> code1 = NOP
00 00 08 00 00 00 00 00  -> text_offset = 0x80000
01 01 08 00 00 00 00 00  -> image_size  = 0x80101
41 52 4d 64  -> magic "ARMd"
```

## Reconstrucción del `boot.img`

```bash
mkbootimg \
  --kernel /mnt/d/ios-a03/stub/kernel.img \
  --ramdisk /mnt/d/ios-a03/stub/stock/ramdisk \
  --dtb /mnt/d/ios-a03/stub/stock/dtb \
  --cmdline "console=ttyS1,115200n8" \
  --base 0x0 \
  --kernel_offset 0x8000 \
  --ramdisk_offset 0x01000000 \
  --tags_offset 0x100 \
  --dtb_offset 0x1f00000 \
  --os_version 11.0.0 \
  --os_patch_level 2025-08 \
  --board SRPUI23B009 \
  --pagesize 2048 \
  --header_version 2 \
  -o /mnt/d/a03/new-boot.img
```

Salida: `D:\a03\new-boot.img`, **1.454.080 bytes**.

```text
sha256(new-boot.img) = 92cf963241890da90deb7b2e5bb066272a269148d29ab5ea2ac23346caa88250
sha256(kernel.img)   = 1c2442b2038c270e1f3636b4b833431565c31133474bab3a793c1ed5e0ec7cb2
```

## Verificación

`unpack_bootimg` sobre `new-boot.img` devuelve los mismos parámetros que el stock, salvo `kernel_size = 524545`.

```text
KERNEL_MATCH_OK          kernel.img == kernel dentro de new-boot.img
PAYLOAD_AT_80000_OK      uart_hello.bin == bytes en 0x80000 de kernel.img
```

## Cómo probarlo

Desde **bootloader fastboot** (no fastbootd):

```bash
adb reboot bootloader
fastboot devices
fastboot boot D:\a03\new-boot.img
```

Si LK no implementa `fastboot boot`, empaquetar `new-boot.img` en un `tar.md5` y flashear solo `boot.img` con Odin. **No incluir LK, SPL ni bootloader.**

## Salida serial esperada

```text
XNU-STUB-OK
EL=1
X0=0x0000000000000000
```

Puerto: `serial1` del DTB, `0x200b0000`, 115200 8N1.

## Notas

- El ramdisk stock se conserva solo para mantener la estructura del `boot.img`; el stub se salta como kernel, así que no lo usa.
- El DTB stock se conserva; XNU recibirá después su propia copia en `boot_args.deviceTreeP`.
- Si sale `EL=2`, falta el `eret` a EL1 en el punto de salto.
- Si no sale nada, confirmar que la consola no está en `serial0` (`0x200a0000`).
