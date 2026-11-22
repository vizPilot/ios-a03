# ios-a03 — XNU 17.7 bring-up en Unisoc T606

> Proyecto de **investigación**. No es un port funcional de iOS y **no distribuye firmware, kernelcache ni binarios de Apple**. El código de XNU está bajo APSL; este repo solo documenta y construye componentes propios.

## Objetivo honesto

Arrancar **XNU 17.7** (`xnu-10063.141.1`, Darwin `23.6.0`, build iOS `21H16`) en un **Samsung Galaxy A03 `SM-A035M`** con **Unisoc T606 / UMS9230**, hasta:

1. Salida por UART.
2. `boot_args` válido y salto a `_start`.
3. Drivers mínimos: UART → timer → GICv3.

**Fuera de alcance:** SpringBoard, UIKit, dyld, SEP, keybags, DRM y cualquier userland cerrado de Apple. El dispositivo destino no tiene Secure Enclave.

## Dispositivos

| Rol | Equipo | SoC | Identificador |
|---|---|---|---|
| Orienteación | iPhone 11 | Apple A13 `t8030` | `iPhone12,1` / `N104AP` |
| Destino | Galaxy A03 | Unisoc T606 `UMS9230` | `SM-A035M` |

El kernelcache del iPhone 11 está cifrado/firmado para `t8030`; **no se reutiliza**. Hay que compilar XNU desde fuente.

## Cadena de arranque elegida

```text
Odin (tar.md5 con solo boot.img)
  → LK carga boot.img
  → payload propio en EL1 (UART/framebuffer primero)
  → boot_args + trampolín
  → salto a _start de XNU
```

`fastboot boot` quedó descartado: LK responde `Unrecognized command boot`. Se usa `boot.img` porque evita reemplazar SPL/LK. El equipo reporta `unlocked: yes` pero también `secure: yes`; ver `docs/03-bootchain-y-boot-img.md` y `docs/06-debug-framebuffer.md`.

## Estado actual

- [x] `.dts` y `.dtb` del A03 analizados.
- [x] DTB validado: magic `0xD00DFEED`, `totalsize = 376049`.
- [x] Bootloader identificado: **LK con SPL de U-Boot**.
- [x] `fastboot getvar unlocked` → `yes`.
- [x] `fastboot getvar secure` → `yes` (ambiguo; requiere prueba empirical).
- [ ] Probar `fastboot boot boot.img` con un boot.img propio sin flashear (o Odin con solo `boot.img` si fastboot lo rechaza).
- [x] Payload compilado: `new-boot.img` (UART) y `new-boot-fb.img` (framebuffer).
- [x] `fastboot boot` descartado: LK responde `Unrecognized command boot`.
- [x] `/dev/mem` no existe: marcador RAM descartado.
- [x] Primer pstore no mostró el marcador; se amplió a los 8 bloques + imem en `D:\a03\new-boot-probe2.img`.
- [x] Causa raíz: falta el trailer `SEANDROIDENFORCE`/`SignerVer02` en `0x1781800`.
- [x] Segunda causa: magic ARM64 estaba en `0x20`, debe ir en `0x38`.
- [x] Ejecución propia en **EL1** confirmada: `kernel-version-probe3-boot.img` → `/proc/version` = `XZ version ...`.
  - Inyección correcta: payload al final del kernel (`0x169e810`) y `code0 = b 0x169e810`; el offset `0x80000` era código vivo.
  - No hacen falta firma Samsung, vbmeta, kexec ni módulos.
- [x] Ramdisk modificado aceptado: `control-ramdisk-concat.img` arrancó a Android con Magisk.
- [ ] Confirmar marcador legible con `control-ramdisk-single.img` (`cat /X`).
- [x] Loader: `boot_args` validado (`BA:47fafc25a0c53650D`) y handoff estilo `_start` validado
  (`:XNUOK`). `/proc/version` sirve como canal de debug desde Android.
- [ ] Cargador de blob: copiar un binario a RAM y saltar a él (`kernel-blob-loader-boot.img`),
  con marcador en `/proc/version` y salida por UART SPRD.
  - Pendiente de sustituir el kernel sintético por un Mach-O de XNU real.
- [ ] Compilar XNU `xnu-10063.141.1` primero en QEMU.
- [ ] Drivers IOKit mínimos para T606.

## Estructura

| Archivo | Contenido |
|---|---|
| `docs/00-estado-actual.md` | Datos verificados del DTB y de fastboot |
| `docs/01-arquitectura.md` | iPhone 11 vs A03, bloqueos duros, mapeo XNU |
| `docs/02-boot-args-y-fdt.md` | `struct boot_args`, offsets y valores del DTB |
| `docs/03-bootchain-y-boot-img.md` | LK/SPL, variables fastboot y plan `boot.img` |
| `docs/04-primeros-drivers.md` | UART, GICv3, timer y brecha de drivers IOKit |
| `docs/05-boot-img-compilado.md` | Parámetros reales, build WSL y verificación del `boot.img` |
| `docs/06-debug-framebuffer.md` | Debug sin serial: buffers, colores y diagnóstico |
| `docs/07-evaluacion-ios26-a71.md` | Evaluación del repo `ssttnd/ios26-a71` como posible base |

## Reglas del repo

1. **Research-only.** No subir IPSW, iBoot, kernelcache, SEP, `dyld`, `UIKit` ni `SpringBoard`.
2. El DTB contiene números de serie (`serial-number`, `androidboot.serialno`); sanitizar antes de publicar.
3. Todo lo que se publique aquí debe ser código escrito por el proyecto o documentación.
4. No prometer "iOS en A03": el objetivo es **XNU en A03**.

## Referencias verificadas

- XNU: `https://github.com/apple-oss-distributions/xnu/tree/xnu-10063.141.1`
- `pexpert/pexpert/arm64/boot.h` y `osfmk/arm64/start.s`
- Kernel Android de referencia: `https://github.com/IverCoder/android_kernel_samsung_a03` (Linux `4.14.199`)
- QEMU A13: `https://github.com/TrungNguyen1909/qemu-t8030`
