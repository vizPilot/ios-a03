# Andamiaje de build: XNU 12377.121.6 para A03 / T606

Estado: **parches generados y verificados para aplicar; kernel NO compilado ni probado.**

Todo lo de aquí es texto fuente. No hay binarios de Apple, kernelcache, KDK,
IPSW ni parches de terceros vendorizados en este repo.

## Contenido

| Ruta | Papel |
|---|---|
| `patches-a03/0001-a03-machine-config.patch` | añade `MACHINE_CONFIG=A03`, `-march=armv8.2-a+crypto`, slice `arm64` sin PAC, sin `lib<A03>.os.*` ni Tightbeam |
| `patches-a03/0002-a03-board-header.patch` | `pexpert/arm64/A03.h`, `board_config.h`, Makefile, `MMU_CLINE` |
| `patches-a03/0003-a03-gic-v3-timer.patch` | GICv3 Group 1 NS, timer INTID 27, SGI 1, `sleh_irq` |
| `patches-a03/0004-a03-master-config.patch` | `config/MASTER.arm64.a03` con `nos_arm_asm`/`nos_arm_pmap` |
| `patches-a03/0005-a03-early-framebuffer.patch` | banda magenta en `start.s`, consola de etapas en `0x9E000000`, hook de panic |
| `patches-a03/0006-a03-stub-apple-internal-headers.patch` | stubs de `sart.h`, `uat.h`, `tunables.s` ausentes en el drop OSS |
| `patches-a03/0007-a03-drop-apple-soc-exports.patch` | quita exportaciones de DART/IOMMU/SART/UAT/Tightbeam |
| `patches-a03/0008-a03-device-tree-platform-expert.patch` | `A03PlatformExpert`, `IONameMatch='sprd,ums9230'` |
| `patches-a03/0009-a03-ramdisk-root-fixes.patch` | `mockfs` y `setRootMedia` sin IOStorageFamily |
| `patches-a03/0010-a03-platform-stubs.patch` | `ml_device_is_prod_fused`, guard de Tightbeam |
| `tools/gen_a03_patches.py` | regenera los parches desde `../xnu-src` (fuente open-source clonada aparte) |
| `tools/verify_a03_patches.sh` | aplica la serie en orden a una copia limpia del árbol |
| `stage-a03.py` | copia la serie a `darwin-xnu-build/patches/26.0` con prefijo `9000-a03-` |

## Datos de plataforma usados

Del DTB del A03 (`D:\a03\a03.dts`, **contiene seriales: no publicar**):

```text
GICv3 distributor  0x10000000 + 0x20000
GICv3 redistrib.   0x10040000 + 0x100000, stride 0x20000
timer PPIs         13, 14, 11, 10  -> CNTV = INTID 27
PSCI               arm,psci-0.2 / smc
framebuffer        0x9E000000, 720x1600, stride 2880 B, BGRA32
página             16K
CPU                4x A75 + 4x A55, ARMv8.2-A, sin PAC
```

## Verificación local reproducible

```bash
python3 xnu/tools/gen_a03_patches.py
bash    xnu/tools/verify_a03_patches.sh
```

La verificación solo prueba que `git apply` acepta la serie en orden; **no
comprueba que compile ni que arranque**.

## Toolchain (bloqueante conocido)

Esto no se puede compilar en la WSL de este equipo. La receta real exige:

```text
macOS 15 (runner macos-15-intel)
Xcode 26.1
KDK 26.1, build 25B5062e
blacktop/darwin-xnu-build @ 663906528d1cd5ea8fde7de6f16de73db9511549
```

`darwin-xnu-build` usa `xcode-select`, `xcrun`, `xcodebuild`, `hdiutil`,
`sw_vers`, `kmutil`, SDK de macOS, KDK, `AvailabilityVersions`, `mig`,
`ctfconvert`/`ctfmerge`, `libfirehose_kernel.a`, etc. Nada de eso existe en
Linux. No hay Docker ni QEMU locales.

## Lo que todavía falta (no está en estos parches)

La serie A71/Bergamota tiene ~267 parches. Ya portados aquí: headers internos,
exports, platform expert, ramdisk-root y stubs de machine routines. Siguen
**sin portar**, como mínimo:

- huecos del KDK cerrado (`0008` de Bergamota: KPC, exports), consola persistente tras TTBR0 (`0012`);
- SMP por PSCI (`0065`) y `rtclock`/timer virtual (`0017`);
- ramdisk como dispositivo virtual (`0024`) y montaje real de root;
- RNG sin CoreCrypto (`0013`, `0014`) y parches de enlace adicionales (`1001`+).

Ese trabajo es el siguiente hito; estos cinco parches son solo la base de
plataforma y la consola visual temprana. SpringBoard/iOS sigue fuera de alcance
(sin SEP, keybags ni userland de Apple).

## Uso (en un Mac, cuando haya acceso)

```bash
git clone https://github.com/blacktop/darwin-xnu-build.git builder
cd builder && git checkout 663906528d1cd5ea8fde7de6f16de73db9511549
python3 /mnt/d/ios-a03/xnu/stage-a03.py --builder "$PWD" [--donor /ruta/Bergamota]
# desde build.sh: MACOS_VERSION=26.1 KERNEL_CONFIG=DEVELOPMENT \
#                 MACHINE_CONFIG=A03 ./build.sh
```

El `--donor` es opcional y **no se guarda** en este repo; sin él el build casi
seguramente fallará por los huecos listados arriba.
