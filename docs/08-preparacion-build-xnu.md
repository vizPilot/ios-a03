# 08 — Preparación del build de XNU para T606

Fecha: 2026-11-22. Estado: **investigación y andamiaje; todavía no hay kernel XNU compilado ni probado.**

## 1. Decisión de versión

El objetivo original del repo era `xnu-10063.141.1` (iOS 17.7 / Darwin 23.6.0). Sin embargo, la
única generación con una receta de build **completa y verificada en hardware no-Apple** es
`xnu-12377.121.6` (iOS 26 / Darwin 25.1.0), usada por `ios26-a71` (`MACHINE_CONFIG=SWEET`) y por
`Bergamota` en el Poco F1.

Decisión de trabajo: **preparar `MACHINE_CONFIG=A03` sobre XNU 12377.121.6**. `10063` queda como
referencia de `boot_args`/`start.s`. Esto no cambia el contrato de arranque ya validado: el loader
Mach-O entrega segmentos, FDT y `boot_args` con `x0 = &boot_args`.

## 2. Toolchain: lo que hay y lo que falta

Inventario real en este equipo (WSL `Ubuntu-24.04`, x86_64):

| Herramienta | Disponible | Sirve para XNU |
|---|---|---|
| `clang 18.1.3` (upstream) | sí | **no**: XNU exige el clang de Xcode con SDK macOS/KDK |
| `ld`, `lld 18` | sí | **no**: se usa `ld` de Apple vía `xcrun` |
| `aarch64-linux-gnu-gcc 13.3` | sí | no: suckless stubs, no kernel Darwin |
| `git`, `python3`, `cmake`, `make` | sí | staging de patches, scripts de empaquetado |
| Docker / QEMU | **no** | no hay ruta de build ni emulación local |
| Xcode + macOS SDK + KDK | **no** | **bloqueante** |

La receta oficial de `apple-oss-distributions/xnu` exige Xcode alineado con la versión de macOS,
Kernel Debug Kit (KDK), `AvailabilityVersions`, headers de XNU/Darwin, `libdispatch`
(`libfirehose_kernel.a`), `libplatform`, `bootstrap_cmds` (`mig`/`migcom`) y `dtrace`
(`ctfconvert`/`ctfmerge`/`ctfdump`). `blacktop/darwin-xnu-build` automatiza todo eso, pero sus
scripts usan `xcode-select`, `xcrun`, `xcodebuild`, `hdiutil`, `sw_vers` y `kmutil`: **no se pueden
ejecutar en Linux**.

Conclusión honesta: el build real solo puede hacerse en **macOS** (Mac local o runner de GitHub
Actions). Este repo no hace `git init`/commit/push, así que el workflow del A71 no se puede lanzar
desde aquí; se deja documentado para ejecutarlo manualmente cuando haya acceso a un Mac.

Puntos fijados por el A71 (referencia, no copia de binarios):

```text
blacktop/darwin-xnu-build  663906528d1cd5ea8fde7de6f16de73db9511549
ry-diffusion/Bergamota      37a7a7a917fc09945ed2f7d1ae68b84d4525b4cb
MACOS_VERSION=26.1  KERNEL_CONFIG=DEVELOPMENT  MACHINE_CONFIG=SWEET
Xcode 26.1  KDK 26.1 build 25B5062e  runner macos-15-intel
```

## 3. Cómo se define una plataforma nueva

`SWEET` no existe en XNU stock: lo crea una serie de patches. Las piezas que hay que reescribir
para `A03` son:

| Archivo XNU | Papel | Adaptación A03 |
|---|---|---|
| `makedefs/MakeInc.def` | `SUPPORTED_ARM64_MACHINE_CONFIGS`, `MACHINE_FLAGS_ARM64_*`, arch string, KDK libs | `+ A03`, `-march=armv8.2-a+crypto`, **sin** `arm64e`, sin `lib<SOC>.os.*` del KDK |
| `config/MASTER.arm64.a03` | configuración del kernel | basada en `MASTER.arm64.sweet`: `nos_arm_asm`, `nos_arm_pmap`, sin CPU counters de Apple |
| `pexpert/pexpert/arm64/A03.h` | constantes de board | GICv3, timer PPI 11, 16K pages, `NO_MONITOR`, `NO_ECORE` |
| `pexpert/pexpert/arm64/board_config.h` | include condicional | `ARM64_BOARD_CONFIG_A03 -> A03.h`, `MAX_CPUS=8` |
| `pexpert/arm64/Makefile` | headers privados | añadir `A03.h` |
| `pexpert/arm/pe_fiq.c` | GIC Group 1 / EOI / BPR | mismo problema de TrustZone que SWEET: Group 0 es de TrustZone |
| `osfmk/arm64/sleh.c` | IRQ del timer | INTID **27** (PPI 11), no 19 como en SWEET |
| `osfmk/arm64/start.s` | mapeo V=P del framebuffer, SCTLR | `0x9E000000`, 720×1600, stride 2880 |
| `osfmk/arm64/{a03_early.c,h}` | consola de arranque | marcas por etapa antes de TTBR0, libre de stack/alloc |
| `pexpert/arm/pe_serial.c` | consola serie | `a03-fbcon` sobre `0x9E000000` (no hay UART usable) |
| `osfmk/kern/debug.c` | panic temprano | llamar a `a03_early_panic()` |
| `osfmk/conf/files.arm64` | lista de fuentes | añadir `a03_early.c` |

## 4. Datos del A03 que debe consumir `A03.h`

Extraídos de `D:\a03\a03.dts` (contiene seriales: **no publicar**):

```text
compatible      = "sprd,ums9230"   / cpuinfo_hardware = "UNISOC T606"
CPU             = 4x Cortex-A75 + 4x Cortex-A55, ARMv8.2-A, sin PAC
GICv3 distributor  = 0x10000000, size 0x20000
GICv3 redistrib.   = 0x10040000, size 0x100000, stride 0x20000, 1 región
timer compatible   = "arm,armv8-timer"
timer PPIs         = 13, 14, 11, 10   -> virtual timer = PPI 11 -> INTID 27
PSCI               = "arm,psci-0.2", method = "smc"
framebuffer        = 0x9E000000, 720x1600, 32bpp BGRA, stride 2880 B
página             = 16K (requerida por XNU arm64, como en SWEET)
```

Diferencias relevantes frente a `SWEET`:

- SWEET (SM7150) numera el timer virtual como PPI 3 → INTID 19; **A03 usa PPI 11 → INTID 27**,
  igual que el valor por defecto de los targets Apple/VMAPPLE. Hay menos código de IRQ que cambiar.
- SWEET usa framebuffer `0x9C000000`, 1080×2400, stride 4320; A03 usa `0x9E000000`, 720×1600,
  stride 2880. Las mismas rutas `dc cvac` ya validadas en `docs/06` aplican aquí.
- El storage de arranque es eMMC (`sdio@201d0000`), no UFS. Para el hito de consola no hace falta
  root filesystem: se puede usar `mockfs` + ramdisk, como hace la serie de Bergamota.
- No hay Adreno, ni `sec_ts`, ni PMIC Qualcomm: **no se aplican** los patches `2xxx-*` del A71.

## 5. Orden de trabajo: qué se puede compilar primero

Orden propuesto, de menor a mayor riesgo:

1. **Solo `MACHINE_CONFIG=A03` + board header**: compilar el kernel hasta `kernel.development.a03`
   y verificar el banner (`strings | grep xnu-12377`). No requiere que arranque.
2. **Consola de etapas en `start.s`/`arm_init`**: bandas y texto en `0x9E000000` usando el mapeo
   V=P del bootstrap TTBR0, con desactivación antes de `arm_vm_init` (copiar la idea de
   `sweet_early`, no su código).
3. **`kprintf` → framebuffer** mediante `pe_serial.c`, con un nodo propio en el FDT/ADT
   (`a03-fbcon`: `reg`, `width`, `height`, `stride`) para no depender de UART.
4. **GICv3 Group 1 + timer INTID 27**, para llegar a `arm_init` → `processor_bootstrap` sin watchdog.
5. Solo después: eMMC/ramdisk/root. **SpringBoard queda fuera de alcance** (sin SEP/keybags).

`docs/06-debug-framebuffer.md` ya validó los pasos previos del contrato: loader Mach-O con
`LC_SEGMENT_64`/`LC_UNIXTHREAD`, `boot_args`, FDT y salto a entry. El kernel XNU será el próximo
consumidor de ese contrato.

## 6. Estado y próximos pasos

- [x] Determinar que el build local en WSL es imposible sin Xcode/KDK y documentar la receta real.
- [x] Elegir XNU 12377.121.6 y `MACHINE_CONFIG=A03`.
- [x] Catalogar los datos de plataforma del A03 y las diferencias con SWEET.
- [x] Obtener la fuente local de XNU 12377 en `xnu-src/` (115 MB, solo fuente open-source).
- [x] Escribir `xnu/patches-a03/` propio, inspirado en la estructura, sin vendorizar parches ajenos.
- [x] Verificar que la serie de 10 parches se aplica en orden sobre un árbol limpio (`xnu/tools/verify_a03_patches.sh`).
- [ ] Portar las familias de parches pendientes (KPC/exports del KDK, PSCI SMP, ramdisk como dispositivo, RNG).
- [x] Publicar el andamiaje en `https://github.com/vizPilot/ios-a03` (124 archivos de texto, sin binarios ni seriales).
- [x] Ejecutar el workflow `xnu-a03.yml` en `macos-15-intel` (run `45080969152`): falló aplicando `9000-a03-0001`.
- [x] Regenerar la serie A03 contra el árbol con 264 parches donantes aplicados: 7 parches, verificados con `git apply`.
- [x] Ejecutar el segundo run (`45083363795`): los parches aplicaron, falló en compilación.
- [x] Corregir las condiciones `arm64e`/Tightbeam invertidas y excluir el framebuffer SWEET del slice A03.
- [x] Tercer run (`45088333954`): **toda la compilación pasó**, falló el enlace (241 símbolos sin definir).
- [x] Añadir `nos_arm_asm`/`nos_arm_pmap`/`pgzalloc` al `MASTER.arm64.a03` y cerrar los guards de Tightbeam/sampler.
- [x] Cuarto run (`45092598433`): falló en `start.s` con `#endif without #if` al entrar por fin el ensamblador open-source.
- [x] Corregir los dos bloques `SWEET` duplicados en `0005` y verificar balance de `#if/#endif`.
- [x] Quinto run (`45096409214`): compilación y enlace casi completos; queda 1 símbolo, `_ml_enable_monitor`.
- [x] Extender el stub vacío de `ml_enable_monitor()` de SWEET a A03 en `machine_routines.c`.
- [x] Sexto run (`45099912009`): **build y enlace correctos**; falló solo la verificación del artefacto.
- [x] Sustituir el `grep` frágil de `A03 EARLY` por `file`/`nm` sobre el Mach-O sin strip.
- [x] Séptimo run (`45103407934`): **build, verificación y publicación correctos**.
- [x] Descargar `kernel.development.a03` (20 897 672 bytes, SHA256 `ada43a4e…f038d53`).
- [x] Corregir el loader Mach-O para segmentos `vmsize==0` y `physBase` real.
- [x] Sanear el DTB (`androidboot.serialno`, `androidboot.un`) y construir `kernel-xnu-boot.img`.
- [ ] **Pendiente de autorización:** flashear con Odin y restaurar el `boot.img` stock.

### Resultado del primer run de GitHub Actions

Los 267 parches de Bergamota se aplicaron correctamente, pero nuestro `0001` fue rechazado:

```text
Required A03 patch rejected: .../9000-a03-0001-a03-machine-config.patch
error: patch failed: makedefs/MakeInc.def:29
error: makedefs/MakeInc.def: patch does not apply
```

Causa: la serie A03 se generó contra XNU prístino y verificado así, pero en el runner se aplica
**después** de los donantes, que ya han tocado `MakeInc.def` y otros archivos de contexto.
La serie se regeneró con `A03_XNU_ROOT` apuntando a un árbol con 264 donantes aplicados; los
parches `0006`, `0007` y `0009` desaparecieron porque el donante ya aportaba esos cambios.
Los 7 parches resultantes pasan `git apply --check` en orden sobre ese árbol.
El log del primer fallo está en el artefacto `xnu-a03-build-log` del run `45080969152`.

### Resultado del segundo run de GitHub Actions

Run `45083363795`: los 7 parches A03 aplicaron limpio y el build llegó a compilación, donde falló
(`make[5]: *** [do_all] Error 2`). Los errores útiles del log fueron:

```text
osfmk/arm64/status.c:140:2: error: call to undeclared function 'MANIPULATE_SIGNED_USER_THREAD_STATE'
bsd/dev/arm64/sysctl.c:431:13: error: call to undeclared function 'ml_task_get_disable_user_jop'
osfmk/vm/vm_shared_region.c:1239:24: error: no member named 'disable_jop' in 'struct pmap'
iokit/Kernel/arm/SweetFramebuffer.cpp:56:10: error: use of undeclared identifier 'PE_parse_boot_argn'
```

Causa raíz: en `MakeInc.def` Bergamota usa `ifneq ($(CURRENT_MACHINE_CONFIG),SWEET)` para quedarse
en `arm64` (sin PAC) y para no enlazar Tightbeam. Al portarlo escribimos
`ifneq ($(filter SWEET A03,...),)`; con `A03` el `filter` devuelve `A03` (no vacío), así que la
condición era **verdadera**: el kernel se compilaba como `arm64e` y activaba PAC/JOP. La corrección
es `ifeq ($(filter SWEET A03,...),)` en esos dos puntos. Además, `SweetFramebuffer.cpp` (parche
donante, 1080×2400 y boot args SWEET) se compilaba en el slice A03; ahora está detrás de la opción
`sweet_iokit`, que no aparece en `MASTER.arm64.a03`.

Dos parches base de `darwin-xnu-build` siguen siendo omitidos por el runner, de forma inocua:
`link_kdk.patch` (no queremos `-force_load libA03.os.*`) y `remove_applefeatures_include.patch`
(el donante ya quitó ese include).

### Resultado del tercer run de GitHub Actions

Run `45088333954`: **compilación completa**, sin errores de C/ensamblador. Falló el enlace:

```text
Undefined symbols for architecture arm64:
  "_CleanPoC_Dcache", referenced from: _dcache_incoherent_io_store64 in caches.o
  "_bcopyin", referenced from: _copyin in copyio.o
  "_pmap_enter_options", ...
  "_sweet_sample_task", referenced from: _sweet_sample_proc in sweet_sample.o
  "_tb_transport_startup", referenced from: _tightbeam_startup in exclaves.o
```

241 símbolos. Causa: `MASTER.arm64.a03` se derivó de `MASTER.arm64.MacOSX`, donde el KDK cerrado
aporta `pmap*.o`, `caches_asm.o`, `start.o`, etc. Bergamota evita eso con
`nos_arm_asm nos_arm_pmap` en `KERNEL_BASE`; nuestro `replace` buscaba una cadena que el donante ya
había cambiado por `ARM_EXTRAS_BASE`, así que no aplicó. Corregido, junto con `pgzalloc` (contenido
en `VM_DEV` de SWEET), el segundo guard de Tightbeam en `exclaves.c` y el bloque
`ARM64_BOARD_CONFIG_SWEET` de `exception.c` que define `sweet_sample_task`.

### Resultado del cuarto run de GitHub Actions

Run `45092598433`: con `nos_arm_asm` activo, `osfmk/arm64/start.s` entró por primera vez en la
compilación y falló en preprocesado:

```text
osfmk/arm64/start.s:2015:2: error: #endif without #if
osfmk/arm64/start.s:743:2: error: #endif without #if
make[7]: *** [start.o] Error 1
```

Causa: el generador de `0005-a03-early-framebuffer.patch` reemplazó el `#if defined(SWEET)` original
por un bloque `#if defined(A03) ... #endif`, dejando el `#endif` del bloque SWEET sin pareja; en el
segundo hunk ocurrió lo contrario (un `#endif /* SWEET */` añadido antes del cuerpo SWEET). Ahora el
generador inserta los bloques A03 **antes** de `#if defined(SWEET)` sin tocar los guards donantes.
La serie se regeneró, pasa `git apply` sobre el árbol donante y un chequeo adicional confirma que
`start.s` no tiene `#endif` sin `#if` ni `#if` sin cerrar.

### Resultado del quinto run de GitHub Actions

Run `45096409214`: compilación completa y enlace reducido a **un solo** símbolo pendiente:

```text
Undefined symbols for architecture arm64:
  "_ml_enable_monitor", referenced from: _arm_vm_init in arm_vm_init.o
```

Bergamota añadió un stub vacío de `ml_enable_monitor()` detrás de `#if defined(SWEET)` en
`osfmk/arm64/machine_routines.c`, porque `arm_vm_init()` lo llama siempre y la definición de Apple
vive en la librería cerrada del SoC. A03 no tiene monitor/PPL, así que se reutiliza el mismo stub
extendiendo el guard a `defined(SWEET) || defined(ARM64_BOARD_CONFIG_A03)`.

### Resultado del sexto run de GitHub Actions

Run `45099912009`: **`Build XNU 12377 for A03` pasó** (32 min) y se generó `kernel.development.a03`.
El job falló después, en `Verify and publish kernel`:

```text
grep -aFq 'A03 EARLY' "$src"   → exit 1
```

El código de consola temprana sí está compilado (`a03_early.o` aparece en el log y los símbolos
enlazan); con `-O2` el compilador puede desplegar `a03_early_string("A03 EARLY ")` en inmediatos
en vez de conservar la cadena contigua, así que el `grep` no era una prueba válida. La verificación
ahora comprueba `file ... arm64`, la cadena de versión y, vía `nm`, que el símbolo
`a03_early_mark` existe en `kernel.development.a03.unstripped.noctf`.

### Resultado del séptimo run de GitHub Actions

Run `45103407934`: **todo el job pasó** (31m50s), incluidos `Verify and publish kernel` y ambos
`upload-artifact`. Artefacto `xnu-a03-kernel` descargado a `build/`:

```text
kernel.development.a03: Mach-O 64-bit arm64 executable
size    : 20 897 672 bytes
SHA256  : ada43a4e9913f08fbfc8d88763d08c7935fbed09a288507b25ce3a6f0f038d53
```

Segmentos: `__TEXT` en `0xfffffe0007004000`, entry `0xfffffe0007583488`
(offset `0x57f488`). El loader copia __TEXT a `0xA2000000`, así que el entry físico es
`0xA257f488`. El binario mide ~20 MB; el máximo del loader es 64 MB, con margen.

Dos correcciones necesarias en `stub/macho_loader.c` antes de integrar:

1. XNU emite segmentos con `vmsize == 0` (`__PRELINK_*`, `__CTF`); `__CTF` además tiene
   `filesize > 0`. El loader los rechazaba con `return 0` y, peor, el `zero-fill` habría
   desbordado. Ahora se saltan.
2. `boot_args.physBase` estaba fijo en `0x80000000`; `start.s` deriva de ahí el delta
   virtual↔físico. Ahora es `KERN_PHYS` (`0xA2000000`), que es donde el loader coloca __TEXT.

El DTB crudo contenía `androidboot.serialno=R9YT719RMRH` y `androidboot.un=H154…`.
`stub/sanitize_dtb.py` los reemplaza por `X` sin cambiar la longitud del blob, manteniendo
válidos todos los offsets. Resultado: `/mnt/d/a03/a03.sanitized.dtb` (376 049 bytes).

`stub/build_xnu_boot.sh` construyó localmente:

```text
/mnt/d/a03/kernel-xnu.img       21 900 960 bytes (Image ARM64)
/mnt/d/a03/kernel-xnu-boot.img  67 108 864 bytes, SHA256 940566ac…3580529c
/mnt/d/a03/kernel-xnu-boot.tar.md5  MD5 a854d9b3147b1cdf0eb3dd7a6993caa8
```

El `boot.img` stock rooteado sigue intacto (SHA256 `5edae458…f271bd`). **No se ha flasheado
nada.** El siguiente paso requiere autorización explícita: Odin con `tar.md5` de solo
`boot.img`, observar framebuffer y restaurar inmediatamente el stock.

### Primer arranque real en dispositivo (usuario autorizó Odin)

Flasheado `kernel-xnu-boot.tar.md5`, restaurado después con `boot-stock-restore.tar.md5`.
Resultado observado: **una franja magenta abajo y se quedó quieto** (sin panic, sin reboot).

Esa franja es exactamente el **stage 0 del parche `0005` en `start.s`**: se pinta apenas entra
`_start_first_cpu`, antes de tocar VBAR, boot args, stacks, tablas de página o MMU:
la banda es de 80×32 px en `x=0..79`, `y=1568..1599`, color `0xffff00ff`.

No apareció el `a03_early_mark(1, "arm_init entered (MMU on)")` de `arm_init.c`, así que XNU
**no llegó a C**. El hang está dentro de `start.s`. Se descartó el único `bne .` que podía
activarse aquí (el chequeo de `SCTLR_EL1_DEFAULT`): el generador ya lo tiene detrás de
`#if !VMAPPLE && !defined(SWEET) && !defined(A03)`. Quedan dos caminos: un `b .` desde un
vector de excepción, o un `bl` a `set_mmu_ttb`/`APPLY_TUNABLES` que no retorna.

El run `45176288504` (instrumentación) falló en 5m52s **antes de compilar**: al promover la
serie se copiaron también los parches sin hunks (`0006`, `0007`, `0009`) que el donante ya
aporta, y el `git apply` del runner abortó con `error: No valid patches in input`. Corregido:
el generador ahora **no escribe** parches sin `@@` y los borra si existen; el verificador los
omite. El repo quedó con 6 parches reales (`0001`–`0005`, `0008`, `0010`).

Por eso el run `45177943774` instrumenta `start.s` con bandas de progreso, todas antes de
cargar la MMU salvo la última:

| Banda | Color | Punto |
|-------|-------|-------|
| 0 | magenta | entrada a `_start_first_cpu` (ya existía) |
| 1 | rojo | boot args guardados en `x20` |
| 2 | amarillo | boot args leídos y stacks listos |
| 3 | cian | `common_start` alcanzado |
| 4 | azul | justo antes de escribir `SCTLR_EL1` |
| 5 | blanco | justo después de activar la MMU |

**Tercera prueba en dispositivo:** aparecieron las 7 bandas (incluidas verde y naranja) y sigue
sin texto. El `ret` está justo después de la naranja; para decidir si el salto a C funciona, el run
`45193782531` añade bandas crudas **9** (primera instrucción C de `arm_init`), **10** (tras
`arm_slide_rebase_and_sign_image`), **11** (tras `arm_static_if_init`) y **12** (tras
`PE_init_platform`), además de reparar el hunk del `a03_early_mark(1)`: el donante Bergamota ya
había reemplazado el prólogo original por llamadas `sweet_early_*`, así que el contexto que buscaba
el generador (`DTEntry chosen = NULL;`) no existía y el mark 1 nunca se enlazó. El texto también se
movió de la parte superior del panel a justo encima de las bandas (y≈1504).

Nota: `sweet_early_set_video()` descarta `Video=0` y `sweet_early_mark` es log-only por defecto,
así que esas llamadas no escriben en el framebuffer ni explican el hang.

Run `45193782531`: build correcto (41m2s). Kernel SHA256
`e95813ecd3a3fb44d8c9ab442f0afafe73b07e4c238140092451baae38428b22` (símbolos
`_a03_early_band`/`_a03_early_mark` y cadena `arm_init entered` confirmados con `llvm-nm`/`grep`).
boot.img SHA256 `0d6cfa53e0e8f050e62abc2a49486574722637004c0f81df097fc175b5c66afc`,
tar.md5 MD5 `c917830c4da548811c9a8c47aff0d189`.

**Cuarta prueba:** solo banda naranja (7), sin banda 9 ni texto. El `ret` a C no aterriza.
Desensamblado: `lr = arm_init` correcto, `bl a03_early_band(9)` compilado, BSS zeroado por el
loader (`__DATA` 0x48000 file / 0x154000 vm). Los 16 vectores de `LowExceptionVectorBase` son
`b .` (silenciosos), así que cualquier excepción al entrar en C es indistinguible del hang.
Para la quinta prueba se parchearon los 16 vectores **en el binario del kernel** (`patch_vectors.py`,
offset de archivo `0x580000`, 72 bytes/slot): cada uno dibuja un bloque blanco 40x32 en
y=1440, x=8+i*44. El tipo de excepción se lee por la posición del bloque. Kernel marcado SHA256
`638c808b60902d810da59d644d3f21006226eeaab5897bfc7e422efc1e35a630`, boot.img SHA256
`3a3a32f8d454d7d83416aac666ded451fd9870efb911ee41a83d88e2227088e4`, tar MD5
`224637e893346d9582de020aed669126`. Sin rebuild de XNU.

**Corrección:** ese primer parche de vectores apuntaba a `LowExceptionVectorBase` (`0x580000`),
pero `VBAR_EL1` se escribe en `common_start` con `_ExceptionVectorsBase` (`0xfffffe000757f000`,
file offset `0x57b000`). Los vectores reales no son `b .` sino branches a handlers en `0x57c000`.
El usuario confirmó que no hubo cambio (solo naranja 7). Se regeneró el marcado sobre `0x57b000`
(16 vectores, bloque blanco 40x32 en y=1440, x=8+i*44). Kernel marcado SHA256
`875a254027632a12c4ca044d286f08d446b07b45affa2b407f1b349682352091`, boot.img SHA256
`5903b1495273de4663f0a19a21cf61ae14ed5bf7d1904b2259125d5acb170770`, tar MD5
`be2bf5c0bbc1d0d5e7f41b984c876884`.

**Sexto resultado:** el usuario envió foto (`D:\a03-apple\20261123_123120.jpg`); confirmó que solo aparecen las
bandas 0–7. Sin bloques de vector, sin banda 9, sin texto. Confirmado que `VBAR_EL1` se escribe con
`_ExceptionVectorsBase` y que los vectores reales saltan a handlers en `0x57c000` (no `b .`). Por tanto
**no hay excepción**: el `ret` se ejecuta pero no hay salida posterior.

**Séptima prueba (diag7, sin rebuild):** `patch_diag7.py` parchea el kernel base `e95813ec…` en dos puntos:
1. `ret` @ `0xfffffe00075855d4` → `b 0xfffffe0007584000`. El stub guarda `x30` en `x16`, dibuja amarillo
   en x=8/y=1440 (stub alcanzado), compara con KVA de `arm_init` (verde x=52), PA `0xa2bee890` (rojo x=96)
   y cero (azul x=140), y salta con `br x16`.
2. `bl a03_early_band` @ `0xfffffe0007bf28d0` → `bl 0xfffffe0007584400`. El stub dibuja magenta en
   x=432/y=1440 y vuelve con `ret`, burlando el guard `early_disabled` para responder si `arm_init` corre.

Kernel `cdd1a6540d760a1f8b8c98c15091172541cf7e681ed123a84c3537b1a0873dd8`, boot.img
`6d6c2b7b4381207f56e2961cc4dc335b232472489df8c14abd56bd5d31d2ac7d`, tar MD5
`4a1d84f256e268a70e21bd050d9a27c0`. Usuario autorizó flashear y restaurar; confirmó restauración de la sexta.

**Séptimo resultado:** amarillo (x=8) + verde (x=52), **sin magenta (x=432)**. Es decir: el `ret` se ejecuta y `x30` es
exactamente la KVA de `arm_init` (`0xfffffe0007bf2890`), pero el `bl a03_early_band` de `arm_init` no se alcanza.
Se descartó BTI como causa: `BTI_ENFORCED=1` en `apple_arm64_common.h`, pero el SCTLR compilado es
`0x000000003454593d` (bit `SCTLR_BT1_ENABLED`, 1<<36, a cero). El stub usaba `br x16`; se cambió por `ret`.

**Octava prueba (`patch_diag8.py`, sin rebuild):** tres sondas independientes.
1. `ret` @ `0x75855d4` → stub con amarillo/verde/rojo/azul en y=1440, terminando en `ret` (no `br`).
2. Primer instruction de `arm_init` @ `0x7bf2890` (`sub sp,sp,#0xd0`) → `b 0x7584800`; el stub dibuja
   magenta en x=432,y=1400, reejecuta `sub sp,sp,#0xd0` y vuelve a `0x7bf2894`.
3. `bl a03_early_band` @ `0x7bf28d0` → stub que dibuja magenta en x=480,y=1400 y vuelve con `ret`.

Lectura: ambos magentas = `arm_init` corre y el fallo es del console C; solo x=432 = muere en el prólogo;
ninguno = el salto a `arm_init` no ocurre. Kernel
`45cfcbf5037385421cd7913aa36d02065445c5788d1df97978efb263514aafb2`, boot.img
`2757a63864c707a836d5828b0cfaec83bc1d5a9bfcfa49bd5cea747c95611a91`, tar MD5
`c91a0b45f0b5e48f8ecc18bdbe151cfa`. Usuario autorizó flashear y restaurar; confirmó restauración de la séptima.

**Octavo resultado:** otra vez amarillo + verde, **sin magenta ni en x=432 (entrada de `arm_init`) ni en x=480
(prólogo)**. Por tanto `x30` es correcto pero el salto a `arm_init` no llega a ejecutar ni su primera
instruction. Se descartó BTI y se cambió `br` por `ret` sin efecto.

**Novena prueba (`patch_diag9.py`, sin rebuild):** diag8 más dos sondas.
- Banda cian en x=176,y=1440 justo antes del `ret` del stub: confirma que el stub llega al final.
- Los 16 vectores reales (`_ExceptionVectorsBase`, file `0x57b000`) dibujan bloque blanco 40x32 en
  y=1360, x=8+i*44, y entran en `b .`. Un bloque blanco identifica la excepción por su x.

Lectura: cian sin magenta + bloque blanco = el `ret` dispara un abort; cian sin magenta sin blanco =
salto a un agujero sin excepción; magenta = `arm_init` sí corre y la observación anterior fue incompleta.
Kernel `044d17760d63ba43400dfd26aca47a6b5ad1dd447654d9c172515e6736af36ce`, boot.img
`50f0157612c113c0416b000037aaf2d50eb9721097240dde8ed095abbc709ac3`, tar MD5
`2d9b592e52eeff600cf057a68fb361e7`. Usuario autorizó flashear y restaurar; confirmó restauración de la octava.

**Noveno resultado:** amarillo + verde + cian, sin magenta y sin bloques blancos. El stub se agota
(cian), `x30` es correcto, y no se toma ninguna excepción (vectores reales verificados en `0x57b000`,
`VBAR_EL1 = 0xfffffe000757f000`). Por tanto el `ret` sale hacia una dirección que no ejecuta ni
falla. Se verificó además que `BTI_ENFORCED=1` pero `SCTLR=0x3454593d` no habilita BTIE.

**Décima prueba (`patch_diag10.py`, sin rebuild):** todas las sondas nuevas se mueven a la fila
y≈1440 que sí es visible, para descartar que y=1400/y=1360 estuvieran fuera del área mostrada.
Mapa: x=8 amarillo, x=52 verde, x=96 rojo, x=140 azul, x=176 cian (fin del stub), x=216 naranja
(`ldr w9,[arm_init]` devuelve `0x17e647dc`, o sea el kernel de RAM sí tiene el parche), x=256 magenta
(entrada de `arm_init`), x=296 magenta (prólogo completado). Vectores siguen marcados en y=1360.
Kernel `c2935b3b58301e3e5df81b88afaf63d7994b05d65d40a1261eaae2d23a46647e`, boot.img
`f6c2646cb463778b510afbac810b46b2dc5bcf084e9fe1aa3126cfd5dfc9e4b8`, tar MD5
`d1e25c59ce5e9da6920d7e8cab52fdcb`. Usuario autorizó flashear y restaurar; confirmó restauración de la novena.

**Décimo resultado:** amarillo + verde + cian, **sin naranja ni magenta**. El parche sí está en el archivo
(`arm_init` primer word `0x17e647dc`, `ret` site `0x17fffa8b`), así que la lectura de datos en KVA no
devuelve el valor esperado. Hipótesis nueva: **la KVA es inutilizable en este punto** (MMU no activo o
TTBR1 mal mapeado). Todas las sondas visibles escriben a la dirección física del framebuffer
`0x9E000000`, así que no demuestran que el MMU esté activo; las bandas 5/6/7 "tras MMU" solo son
etiquetas de código, no prueba de traducción.

**Undécima prueba (`patch_diag11.py`, sin rebuild):**
- x=8 amarillo, x=52 verde, x=176 cian como antes.
- x=216 azul si `SCTLR_EL1.M=1`, blanco si `M=0` (lea `mrs x9,sctlr_el1; and x9,x9,#1`).
- El stub ya NO vuelve con `ret` a `x30` (KVA), sino que hace `br` a la dirección **física** de
  `arm_init`, `0xa2bee890`, alcanzable tanto con MMU apagado como con el mapeo V=P de TTBR0.
- x=256 magenta al entrar en `arm_init`; x=296 magenta al completar el prólogo.
- Vectores marcados en y=1360.

Kernel `5ce0d7d2372f80ff5391ef35a10abbb8d41c806cca54ef780c450b56129b8261`, boot.img
`cff75a3fc465d61f407ccd1d28057a56a7c1b613337059ced93279d7055db6f3`, tar MD5
`c40f8f28da1122df32b74b730d47a61d`. Usuario autorizó flashear y restaurar; confirmó restauración de la décima.

**Undécimo resultado:** rojo en x=216 (`SCTLR_EL1.M=1`, MMU **sí** activa) y un magenta nuevo; sin banda 9 ni texto.
El `br` a la dirección **física** de `arm_init` (`0xa2bee890`) sí entra en C, mientras que el `ret`/`br` a su
KVA (`0xfffffe0007bf2890`) no. Por tanto el problema con la KVA es de mapeo/traducción, no de MMU apagada.
La V=P (`TTBR0`) funciona.

**BUG REAL ENCONTRADO (duodécima prueba):** el desensamblado del kernel base muestra que la banda 7 de
depuración sobrescribe `x0` justo antes del `ret`:

```
0xfffffe0007585584  add  x0, x20, x22   <- boot_args KVA
0xfffffe0007585588  sub  x0, x0, x23
0xfffffe000758558c  ... dibujo banda 7, destruye x0 ...
0xfffffe00075855d0  dsb  sy
0xfffffe00075855d4  ret                 <- arm_init recibe x0 = 0x9e44f0c0
```

El parche A03 insertó la banda entre la construcción de `x0` y el `ret`. `arm_init` recibe la dirección
del framebuffer en vez de `boot_args`. La duodécima prueba NOPea esas 18 instrucciones (`0x758558c`–
`0x75855d0`) desde binario, mantiene el salto físico a `arm_init`, y añade: x=336 blanco si
`x0 == x20+x22-x23`, x=256 magenta (entrada) y x=400 naranja (prólogo) para distinguirlos sin ambigüedad.
Kernel `524e9d4bc82115d4119f29c6f35002e6a4d3d11ef43a4a58fef9c25525e14a0d`, boot.img
`5ddf9862d5b6b8c45b9614346ed6120733c64f82bb157a47b4c95c41dfc7b2af`, tar MD5
`bea18bb5c308f2ae2e0ddc5c2136d029`. Usuario autorizó flashear y restaurar; confirmó restauración de la undécima.

**Segunda prueba en dispositivo:** aparecieron las 6 bandas (magenta, roja, amarilla, cian,
azul y blanca) y **ningún texto**. La blanca confirma que la MMU se activó; el hang está entre
`isb` (post-`SCTLR_EL1`) y el `a03_early_mark(1)` de `arm_init.c`. `HAS_CLUSTER` no está
definido para A03, así que el bloque `CPU_OVRD` (registro Apple) se omite, descartado.

El run `45184015200` añade dos bandas más: verde 6 tras escribir `CPACR_EL1` (NEON) y naranja 7
justo antes del `ret` a `arm_init`. Build correcto (40 min, tras un corte de luz local que solo
afectó al `gh` watch). Kernel SHA256 `a41db80d348437825ed7a94f35b261ba4d23b5c816521b8f2629e6e38f656806`,
boot.img SHA256 `d14bfeeefae84115befe35290da4684f2a752210816db586c5dcbdf237f822c1`,
tar.md5 MD5 `c8a1c0d614a4f58fdb9a336c7c0ecb72`.

Run `45177943774`: build y publicación correctos (28m30s). Kernel instrumentado
SHA256 `1d82b9541bbd13104ff6b36ddfbb12bb2f2aa9e6e20e2dd8f70bb64fa25a5a1c`.
`kernel-xnu-boot.img` SHA256 `7e543a17bc02f244893c85637c952abe8d9de0abf0a3162b56e63f5362ca00a5`,
tar.md5 MD5 `fbba20a0a42fdd665a16b10c805f1d15`.

Si aparece la banda N pero no la N+1, el fallo está entre esos dos puntos. El `verify` de la
serie se endureció además para omitir parches sin hunks (`0006`, `0007`, `0009` ya los aporta
el donante), de modo que `git apply` no se detenga en un archivo vacío.

## 7. Andamiaje creado

```text
xnu/patches-a03/0001-a03-machine-config.patch       MACHINE_CONFIG=A03, arm64 sin PAC
xnu/patches-a03/0002-a03-board-header.patch         A03.h, board_config, MMU_CLINE
xnu/patches-a03/0003-a03-gic-v3-timer.patch         GIC Group 1 NS, INTID 27, sleh_irq
xnu/patches-a03/0004-a03-master-config.patch        MASTER.arm64.a03, nos_arm_asm/nos_arm_pmap
xnu/patches-a03/0005-a03-early-framebuffer.patch    banda magenta + consola de etapas
xnu/patches-a03/0008-a03-device-tree-platform-expert.patch
xnu/patches-a03/0010-a03-platform-stubs.patch
xnu/tools/gen_a03_patches.py                        regenerador con A03_XNU_ROOT
xnu/tools/verify_a03_patches.sh                     git apply sobre el árbol donante
xnu/stage-a03.py                                    staging en darwin-xnu-build
xnu/README.md                                       toolchain, datos y trabajo pendiente
```

La serie cubre los pasos 1, 2 y 4 del orden de trabajo de la sección 5: configuración de
plataforma, consola visual temprana y enrutado de interrupciones. El paso 3 (`kprintf` →
framebuffer vía `pe_serial.c`) y el 5 (eMMC/ramdisk) siguen pendientes.

`D:\a03\boot.img` sigue intacto (SHA256 `5edae4587433340212b9d730885b36cde7feee195807c54eabeb3cfa26f271bd`,
sin cambios desde el 20/11): no hace falta restaurarlo después de la última prueba Mach-O.

**Honestidad:** hoy no existe XNU compilado para T606. Lo que existe es un cargador Mach-O
funcional y una serie de siete parches que `git apply` acepta limpiamente **después** de los
donantes. El segundo run demostró que aplicar no basta: la primera compilación falló por una
condición `arm64e` invertida y por código SWEET arrastrado al slice A03; ambos están corregidos,
pero **queda verificar el siguiente run**. No hay Xcode/KDK en este equipo y la serie completa de
Bergamota sigue siendo necesaria para que el build enlace.
