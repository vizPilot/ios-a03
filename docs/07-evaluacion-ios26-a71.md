# Evaluación: ¿usar `ssttnd/ios26-a71` como base para iOS 26 en el A03?

Fecha: 2026-11-21. Repo analizado: <https://github.com/ssttnd/ios26-a71> (`main`, 444 archivos).

## Resumen

**Sí como referencia de ingeniería y andamiaje de build; no como base "drop-in".** El repo demuestra
algo real: iOS 26.6.2 (`23G90`) de `iPhone12,1` arranca en un Galaxy A71 4G (`SM-A715F`) con
Snapdragon 730. Pero casi todo ese éxito depende de que el A71 comparte plataforma con el Redmi
Note 10 Pro (`sweet`, `SM7150`), para el que ya existía un ports de XNU 12377 con drivers.

El Galaxy A03 es **Unisoc T606 / UMS9230**: no comparte ni el SoC, ni el storage path, ni el mapa
de memoria, ni los drivers con el A71. Además, en el A03 todavía no hemos resuelto el bloqueo
previo: el bootloader parece aceptar ramdisk modificado pero rechazar kernel modificado.

## Qué es realmente lo que arranca en el A71

| Capa | Origen |
|---|---|
| Kernel | XNU **12377.121.6** recompilado desde fuente (blacktop/darwin-xnu-build + Bergamota), con `MACHINE_CONFIG=SWEET` y patches del repo |
| Userland | Root HFSX construido desde el IPSW de iPhone 11 (`23G90`), **no distribuido** en el repo |
| Identidad | ADT `N104AP` generado con direcciones del A71, no el ADT del iPhone |
| Arranque | `boot` partition contiene el **shim**, que actúa como iBoot:lee un payload `SWEETXNU` desde el ramdisk, copia segmentos, coloca ADT + `boot_args` y salta a XNU |
| Storage | UFS en `0x01d84000`, con un probe propio en `shim/ufs.c` y driver en el kernel |
| Gráficos | CPU renderer primero; después Metal native sobre Adreno 618 con firmware del propio A71 |

Punto importante: **no reutilizan el kernelcache cifrado del iPhone 11**. Compilan XNU abierto y
parchean el userland (`MobileGestalt`, `launchd`, `lockdownd`) para que acepte la plataforma. Eso
valida la estrategia que ya teníamos, pero con XNU 12377 en vez de 17.7.

## Por qué no es portable directo al A03

| Subsistema | A71 / sweet | A03 |
|---|---|---|
| SoC | Qualcomm SM7150 | Unisoc UMS9230 / T606 |
| Boot | ABL pasa DTB en `x0`, permite reemplazar kernel | LK pasa `boot_args`, y aparentemente verifica kernel |
| Storage | UFS `ufshc@1d84000` | eMMC `sdio@201d0000` es el `boot_device`; hay UFS en `0x20200000` pero no es el path de arranque |
| UART | Qualcomm, otro layout | SPRD `serial1` en `0x200b0000`, offsets propios |
| Framebuffer | `0x9c000000`, 1080x2400 | `0xfd380000`, 1600x720 (`lcd_base=9e000000` para logo) |
| GIC | GICv3 en `0x17a00000`, PPI vtimer 19 | GICv3 en `0x10000000`, ver DT del A03 |
| GPU | Adreno 618 + firmware A71 | Mali-G57, sin stack en el repo |
| Touch | `sec_ts` S6SY771 en I2C QUPv3 | backend Unisoc, otro driver |

Los patches `xnu/patches-12377/` (todo el trabajo de touch, USB, GPU, batería, Wi-Fi, audio,
brillo, etc.) están escritos contra `osfmk/arm64`, `pexpert` y drivers de SM7150. No se pueden
aplicar al T606: habría que escribir equivalentes nuevos.

## Qué se puede reutilizar de verdad

1. **El patrón del shim.** `shim/loader.c` es un excelente modelo para nuestro trampolín:
   - lee `linux,initrd-{start,end}` del DTB;
   - valida un payload `SWEETXNU`;
   - copia segmentos con MMU off;
   - construye `boot_args` (Revision/Version 2, `deviceTreeP`, `CommandLine`, `Video`);
   - salta a XNU con `x0 = boot_args_pa`.
   Nuestro `stub/uart_hello.S` hoy hace solo el primer marcador; conviene migrar a este diseño.
2. **Herramientas de empaquetado:** `tools/mkpayload.py`, `mkadt.py`, `adt.py`, `mkbootv2.py`,
   `samsung-tar.py`, `hfsread.py`, `mkinit.py`. Son código propio y genérico; se pueden
   vendorizar con su licencia, sin copiar firmware ni datos del A71.
3. **El workflow de GitHub Actions** para compilar XNU 12377 con Xcode (nosotros hoy compilamos el
   payload en WSL; el kernel completo necesita macOS).
4. **La idea de generar el ADT del iPhone 11 con direcciones del destino**, en vez de usar el DTB
   de Android como `deviceTreeP`.
5. **El enfoque de "root preparado + payload de sistema"** para el userland de iOS 26.

## Qué NO se puede reutilizar

- El kernel ya compilado (`kernel.development.sweet`): tiene `MACHINE_CONFIG=SWEET` y código de
  SM7150; haría panic en el T606.
- El DTB del A71 y sus constantes de GIC/UART/framebuffer/UFS.
- `shim/ufs.c` tal cual: el A03 arranca desde `sdio@201d0000` (eMMC), no desde ese UFS.
- Los patches de Adreno/SEC_TS/Wi-Fi/PMIC/batería.
- Cualquier IPSW, root HFSX, firmware del teléfono o binario de Apple: se generan/obtienen localmente.

## El bloqueo que viene antes que iOS 26

En el A03 no hemos logrado ejecutar ni nuestro payload de 200 instrucciones:

- `new-boot-injected.img` = kernel stock + payload en `0x80000` + trailer Samsung: se queda en logo.
- `control-stock-rebuild.img` es byte-idéntico al stock, así que el builder es correcto.
- `control-ramdisk-mod.img` = kernel stock + ramdisk modificado: **entró en bucle en el logo**.
  Después se descubrió que nuestro empaquetador CPIO estaba mal: convertía todos los entries en
  archivos `0644`, descartaba directorios y dejaba `init` sin ejecutar. No es una conclusión sobre
  firmas. Ver `docs/06-debug-framebuffer.md`.
- `control-ramdisk-concat.img` = kernel stock + ramdisk stock + 95 bytes: **arrancó a Android**
  con Magisk funcionando, aunque el marcador concatenado no fue extraído. Confirmado: **LK acepta
  ramdisk modificado**.
- `control-ramdisk-single.img` = kernel stock + CPIO recomprimido con `/X`: **resultado pendiente**.

Con el ramdisk ya descartado como causa, el siguiente bloqueo era el kernel. **Resuelto:** LK acepta
un `boot.img` con kernel modificado siempre que el payload se inyecte al final del archivo y no
sobrescriba código vivo (el entry real está en `0x1200000`, no en `0x80000`). No hace falta firma
ni vbmeta. Ver `docs/06-debug-framebuffer.md`.

kexec no está disponible (`CONFIG_KEXEC` no está compilado), pero `CONFIG_MODULES=y` y
`CONFIG_MODULE_SIG` no está activo: se pueden cargar módulos propios. Es una ruta paralela, aunque
el payload inyectado en el `boot.img` ya da ejecución en EL1 desde el arranque.
Las salidas serían:

1. **kexec desde Android rooteado.** Probar en el boot rooteado stock:
   ```sh
   adb shell 'id; cat /proc/sys/kernel/kexec_load_disabled; zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_KEXEC|CONFIG_KEXEC_SIG|CONFIG_MODULES"; command -v kexec'
   ```
   Si `CONFIG_KEXEC=y` y `kexec_load_disabled=0`, podemos cargar el shim con un initrd que
   contenga el payload XNU y el DTB del A03, y saltar desde userspace sin pasar por la verificación
   de LK. Es la ruta más prometedora y reutiliza casi todo el diseño del repo.
2. **Módulos de kernel / exploit de LK.** Si `CONFIG_MODULES` está permitido o hay una dereferencia
   de funciones en el ramdisk, se podría meter el trampolín en EL1. Más frágil.
3. **Firmar/evadir la verificación.** No es deseable para este proyecto y depende de claves de
   Samsung; fuera de alcance.

## Recomendación

1. Terminar primero el test de `control-ramdisk-mod.img` y restaurar el boot rooteado stock.
2. Probar kexec en el boot rooteado antes de escribir una sola línea de soporte para iOS 26.
3. Solo después migrar el objetivo de XNU 17.7 a **XNU 12377**, porque el userland de iOS 26 no
   arranca con Darwin 23.6.0. El `boot_args` y el contrato de arranque ya verificados siguen siendo
   válidos; cambia la versión del kernel y el conjunto de patches.
4. Crear `MACHINE_CONFIG=A03` y `xnu/patches-a03/` nuevos, no aplicar `patches-12377` directamente.
5. Mantener este repo como lugar de los datos del A03; usar el repo de A71 como *referencia*
   (build, shim, ADT, root prep), nunca como fuente de binarios.

**Conclusión honesta:** el repo prueba que el enfoque es viable en hardware cercano y nos da un
diseño de loader muy útil. No convierte el A03 en un A71: el trabajo real está en el puerto de
plataforma Unisoc y en resolver cómo ejecutar código propio en EL1. Incluso con todo eso, el
resultado sería un research-only con UI parcial y sin SEP, no "iOS 26 funcional en el A03".

## Fuentes consultadas

- `README.md`, `NOTES.md`, `AGENTS.md`, `docs/INSTALL.md`, `docs/galaxy-a71-port.md`
- `shim/loader.c`, `shim/shim.c`, `shim/start.S`, `shim/mmu.c`, `shim/fdt.c`, `shim/ufs.c`
- `.github/workflows/xnu26.yml`, `xnu/patches-12377/`, `xnu/patches-12377-adreno/`
- `D:\a03\a03.dts` (bootargs y nodos `sdio@201d0000`, `ufs@20200000`, GIC, framebuffer)
