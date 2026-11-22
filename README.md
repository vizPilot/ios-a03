# ios-a03 — XNU en Galaxy A03 (SM-A035M, Unisoc T606)

> Proyecto de **investigación**. No es un port funcional de iOS y **no distribuye firmware, kernelcache, iBoot, SEP, binarios de Apple ni IPSW**. El código de XNU está bajo APSL; aquí solo hay componentes propios, documentación y un workflow de compilación.

## Objetivo honesto

Llegar a una **consola XNU propia** en `SM-A035M` con **Unisoc T606 / UMS9230**:

1. `boot.img` propio cargado por LK (sin tocar SPL ni LK).
2. Payload en EL1 con framebuffer debug.
3. Handoff estilo iBoot: `boot_args` + FDT + salto al entry de un Mach-O.
4. Kernel XNU compilado para ARM64 con `MACHINE_CONFIG=A03`.
5. Drivers mínimos: framebuffer, GICv3 Group 1 NS, timer virtual.

**Fuera de alcance:** SpringBoard, UIKit, dyld, SEP, keybags, DRM y cualquier userland cerrado de Apple.

## Estado actual

- [x] DTB analizado (`0xD00DFEED`, `totalsize=376049`), UART SPRD `0x200b0000`.
- [x] `boot.img` stock reconstruido byte a byte; trailer Samsung en `0x1781800`.
- [x] Ejecución propia en EL1 confirmada vía `/proc/version`.
- [x] Framebuffer calibrado: `0x9E000000`, 720×1600, BGRA32, stride 2880.
- [x] Loader Mach-O validado con binario sintético (`LC_SEGMENT_64`, `LC_UNIXTHREAD`, `boot_args`, FDT).
- [x] XNU `12377.121.6` clonado como fuente local (solo fuente, fuera del repo publicado).
- [x] 10 parches A03 generados y verificados (`git apply` en orden sobre árbol limpio).
- [x] Workflow `xnu-a03.yml` para `macos-15-intel` + Xcode 26.1 + KDK.
- [ ] Ejecutar el workflow y obtener `kernel.development.a03`.
- [ ] Integrar el kernel real con `stub/build_macho_boot.sh`.
- [ ] Drivers IOKit mínimos para T606.

## Compilación en GitHub Actions

El repo público `https://github.com/vizPilot/ios-a03` incluye `.github/workflows/xnu-a03.yml`:

- `workflow_dispatch` en `macos-15-intel`.
- Descarga `darwin-xnu-build@663906528d` y `Bergamota@37a7a7a9` como donante local (no vendorizado).
- `xnu/stage-a03.py` copia la serie `0001`–`0010` con prefijo `9000-a03-` y añade `arm64` a las arquitecturas.
- Sube `kernel.development.a03` y `build.log.gz` como artefactos.

El build **no se ha ejecutado todavía**; el resultado puede fallar por huecos del KDK cerrado que faltan por portar (ver `xnu/README.md`).

## Estructura

| Ruta | Contenido |
|---|---|
| `docs/00`–`docs/08` | Investigación, debug por framebuffer y preparación del build |
| `stub/` | Payload ARM64, loader Mach-O y scripts de ensamblado del `boot.img` |
| `xnu/patches-a03/` | 10 parches A03 generados reproduciblemente |
| `xnu/tools/gen_a03_patches.py` | Generador desde `xnu-src` (no incluido en el repo) |
| `xnu/tools/verify_a03_patches.sh` | Verificación `git apply` sobre copia limpia |
| `xnu/stage-a03.py` | Staging en `darwin-xnu-build` |
| `.github/workflows/xnu-a03.yml` | Build remoto en macOS |

## Reglas del repo

1. **Research-only.** No subir IPSW, iBoot, kernelcache, SEP, `dyld`, `UIKit` ni `SpringBoard`.
2. El DTB local contiene números de serie (`serial-number`, `androidboot.serialno`); **no publicar** `a03.dtb`/`a03.dts`.
3. Todo lo publicado es código escrito por el proyecto o documentación; los parches de terceros se descargan en el runner, nunca se vendorizan.
4. No prometer "iOS en A03": el objetivo es **XNU en A03**.
