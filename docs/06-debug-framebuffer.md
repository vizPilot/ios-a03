# 06 — Debug sin serial: huella por framebuffer

## Por qué cambiar de medio

La salida serial no apareció. Antes de seguir, hay que distinguir tres causas:

1. El `boot.img` propio **no se ejecutó** (firma/secure boot/offset).
2. El payload **sí corrió**, pero la UART no está donde creemos o su clock real no es 26 MHz.
3. LK apagó el display antes de saltar al kernel.

Un test de framebuffer responde a las tres sin necesidad de UART.

## Buffers candidatos del DTB

| Nodo | Dirección | Tamaño en DTB |
|---|---:|---:|
| `logobuffer@9e000000` (`lcd_base` del `bootargs`) | `0x9E000000` | `0xAB0000` |
| `framebuffer-mem@fd380000` (`fb_reserved`) | `0xFD380000` | `0x1300000` |

Resolución: `1600x720` (`hactive = 0x2D0`, `vactive = 0x640`), `logo_bpix = 24`.

El payload escribe `0x465000` bytes (= `1600*720*4`) en ambos, para cubrir RGB24 y RGBA32:

| Buffer | Patrón | Color esperado |
|---|---|---|
| `0x9E000000` | `0xFF` | Blanco |
| `0xFD380000` | `0x00` | Negro |

## Interpretación

| Lo que ves | Diagnóstico |
|---|---|
| Pantalla **blanca** | El payload corrió; el buffer vivo es `0x9E000000` (splash de LK) |
| Pantalla **negra** | El payload corrió; el buffer vivo es `0xFD380000` (framebuffer de kernel) |
| Pantalla **mitad blanca / mitad negra** | Ambos buffers están being shown/compositeados; aún así hubo ejecución |
| **Sin cambio** (sigue Android/logo) | El payload no se ejecutó, o LK apagó el display |

Si no hay cambio, el siguiente paso no es seguir con drivers, sino verificar aceptación del `boot.img` y el punto de salto.

## Cambio importante en la UART

El payload anterior reprogramaba el divisor con `26000000 / 115200 = 225`. Ese valor solo es válido si el clock real del UART es 26 MHz; el driver usa 26 MHz como *fallback*, pero `clk_get_rate(clk_uart)` puede devolver otro valor.

Por eso `UART_REINIT` ahora es **0 por defecto**: el payload no toca `CLKD0/CLKD1/LCR/CTL1`, solo escribe en `TXD` confiando en la configuración que dejó LK.

Para volver al modo anterior:

```bash
make clean
make UART_REINIT=1
```

## Artefactos generados

```text
D:\ios-a03\stub\kernel-fb.img     524.612 bytes (0x80144)
D:\a03\new-boot-fb.img          1.454.080 bytes
```

```text
sha256(kernel-fb.img)    = ef27543c570dbd1d59d982ca578b9fddddd1a0c07261ff4d8cc50f99227ed89e
sha256(new-boot-fb.img)  = 23c9c1efecf1713b39b1d01d84e6ff4bf3d73afec460446928d47cd549ae79bb
```

Literal verificado en el ELF:

```text
91000118: 9e000000  .word 0x9e000000
91000120: fd380000  .word 0xfd380000
```

## Prueba

```bash
adb reboot bootloader
fastboot boot D:\a03\new-boot-fb.img
```

O Odin con un `tar.md5` que contenga **solo** `boot.img`.

## Resultado observado: Odin → logo de Samsung

El usuario flasheó `new-boot-fb.img` con Odin; el equipo se quedó en el logo de Samsung Galaxy y luego se restauró el `boot.img` stock rooteado.

Eso **no confirma** que el payload haya corrido. Con `secure: yes`, LK puede rechazar una imagen flasheada y quedarse en el splash antes de saltar al kernel.

Flujo seguro a partir de ahora:

1. No flashear más imágenes experimentales con Odin.
2. `adb reboot bootloader`.
3. `fastboot boot D:\a03\boot.img` → debe llegar a Android.
4. Si funciona, `fastboot boot D:\a03\new-boot-fb.img`.
5. Solo si `fastboot boot` falla por completo, volver a Odin como último recurso.

El `boot.img` rooteado sirve además para leer un marcador de ejecución desde Android con `su` (`/dev/mem` o `devmem`), aunque eso se hará en el siguiente paso.

## `fastboot boot` no existe en este LK

Ejecutado:

```text
fastboot boot D:\a03\new-boot-fb.img
Sending 'boot.img' (1420 KB)  OKAY
Booting                       FAILED (remote: 'Unrecognized command boot')
```

El image se envía pero el comando `boot` no está implementado. Por tanto **Odin es el único camino** en este dispositivo.

## Marcador de ejecución: `new-boot-marker.img`

Artefacto: `D:\a03\new-boot-marker.img` (1.454.080 bytes).

```text
sha256 = b9626864226e3bee3800e280439ae21f2246dfb51c924fd1ba2c48c5d4f1cfd4
```

El payload escribe en la zona reservada `sec_dbg@0x8F000000`:

| Dirección | Valor | Significado |
|---|---|---|
| `0x8F000000` | `0x58535542` | `"XSUB"` — magia de ejecución |
| `0x8F000004` | `0..3` | `CurrentEL` |
| `0x8F000008` | low32 | `x0` bajo |
| `0x8F00000C` | high32 | `x0` alto |
| `0x8F000010` | `0xA03FB001` | ID del build |

Flujo:

1. Odin → flashear `new-boot-marker.img` como `boot.img`.
2. Arrancar; aunque se quede en el logo, apagar.
3. Odin → restaurar `boot.img` rooteado stock.
4. Ya en Android con root:

```bash
adb shell su -c 'busybox devmem 0x8F000000 32'
adb shell su -c 'busybox devmem 0x8F000004 32'
adb shell su -c 'busybox devmem 0x8F000008 32'
adb shell su -c 'busybox devmem 0x8F00000C 32'
adb shell su -c 'busybox devmem 0x8F000010 32'
```

Si `busybox devmem` no está disponible:

```bash
adb shell su -c 'dd if=/dev/mem bs=4 count=5 skip=$((0x8F000000/4)) 2>/dev/null | od -An -tx4'
```

Interpretación:

| Lectura | Conclusión |
|---|---|
| Magia e ID correctos | El payload **sí corrió**; mirar `EL` y `x0` |
| Todo a cero | No corrió, o `/dev/mem` está restringido |
| Magia correcta pero `EL=2` | Falta `eret` a EL1 |

## Cambio de marcador: pstore/ramoops

`/dev/mem` no existe en el kernel del A03, así que el marcador en `0x8F000000` no se puede leer desde Android. Cambiamos a **pstore/ramoops**, que sí se expone como archivo en `/sys/fs/pstore/`.

### Zona elegida

Del DTB:

```dts
ramoops@fff80000 {
    compatible = "ramoops";
    reg = <0x00 0xfff80000 0x00 0x40000>;
    record-size = <0x8000>;
    console-size = <0x8000>;
    pmsg-size = <0x8000>;
};
```

Con 6 zonas de dump de `0x8000`, la zona de consola queda en:

```text
0xFFF80000 + (6 * 0x8000) = 0xFFFB0000
```

### Formato escrito

El payload escribe una cabecera `persistent_ram_buffer` válida:

```c
struct persistent_ram_buffer {
    uint32_t sig;      /* 0x43474244 = "DBGC" */
    atomic_t start;    /* 0 */
    atomic_t size;     /* 19 */
    uint8_t  data[];   /* "XSUB A03FB001 EL=<n>\n" */
};
```

Cuando el kernel stock arranca, pstore detecta la firma válida, guarda el buffer como `console-ramoops-*` y lo expone en `/sys/fs/pstore/`.

### Artefacto

```text
D:\a03\new-boot-pstore.img      1.454.080 bytes
D:\ios-a03\stub\kernel-pstore.img  524.776 bytes
```

```text
sha256(new-boot-pstore.img) = 5ec8a9c5e26435d7218d647833d4b071ecd9b8090bad88d78dd0ca4bc3cabc7f
sha256(kernel-pstore.img)   = f987d0f33e7e1a0cb3749451fd1983a30a9e556eea02bfc901bdf43a47b95613
```

Literal verificado en el ELF:

```text
910000ec: movk w1, #0x4347, lsl #16    (sig)
910001a0: .word 0xfffb0000             (PSTORE_CONSOLE_BASE)
```

### Procedimiento

1. Odin → flashear `new-boot-pstore.img` como `boot.img`.
2. Arrancar; aunque se quede en el logo, apagar.
3. Odin → restaurar `boot.img` rooteado stock.
4. Ya en Android con root:

```bash
adb shell
su
ls -l /sys/fs/pstore/
cat /sys/fs/pstore/console-ramoops*
```

### Interpretación

| Resultado | Conclusión |
|---|---|
| Aparece `XSUB A03FB001 EL=<n>` | El payload **sí corrió**; mirar `EL` |
| No aparece nada en pstore | No corrió, o la zona de consola es otra |
| Aparece pero con `EL=2` | Falta `eret` a EL1 |

Si no aparece, el siguiente paso es escribir el marcador en **todas** las zonas ramoops posibles (hay 8 bloques de `0x8000` en `0x40000`) para garantizar que al menos una sea la que pstore lee.

## Resultado del primer intento pstore

El `cat /sys/fs/pstore/console-ramoops*` mostró logs del kernel stock (0..112s, terminando en `reboot: Restarting system with command 'bootloader'`), pero **no** el mensaje `XSUB A03FB001 EL=<n>`.

Además, los logs revelaron algo importante:

```text
sec_debug:__sec_debug_dt_addr_init() restart_reason addr : (0x81b5d7e0)
sec_debug:__sec_debug_dt_addr_init() upload_cause addr : (0x81b657e4)
sec_debug:__sec_debug_dt_addr_init() sprd imem dt set!!!
sec_debug:sec_debug_set_upload_cause() cafebabe
```

Del DTB se confirma el imem:

```dts
imem@7E0 {
    compatible = "unisoc,sprd-imem";
    ranges = <0x00 0x00 0x7e0 0x20>;
    reg = <0x7e0 0x20>;
    upload_cause@4  { reg = <0x04 0x04>; };
    restart_reason@0 { reg = <0x00 0x04>; };
};
```

Es decir:
- `restart_reason` = `0x7E0` (física)
- `upload_cause` = `0x7E4` (física)

El kernel stock escribe `0xCAFEBABE` en `upload_cause` cada arranque. Si nuestro payload escribe algo distinto ahí justo antes, podremos verlo.

## Intento 2: `new-boot-probe2.img`

Artefacto: `D:\a03\new-boot-probe2.img` (1.454.080 bytes).

```text
sha256 = 7675ea34a09c88ea966028080189b7d9301f3e6528d9947a0dac98f3cc787f0a
```

El payload ahora escribe marcadores en **tres sitios**:

1. `restart_reason` (`0x7E0`) = `0xA03FB001`.
2. `upload_cause` (`0x7E4`) = `"XSUB"` (`0x58535542`).
3. **Todos los 8 bloques** de ramoops (`0xFFF80000..0xFFFC0000`, bloques de `0x8000`) con la cabecera `DBGC` y el mensaje `XSUB A03FB001 EL=<n>`.

Esto cubre cualquier layout de pstore sin depender de cuántas zonas de dump haya.

Literal verificado en el ELF:

```text
910001d0: .word 0x000007e0       (restart_reason)
910001e0: .word 0xfff80000       (RAMOOPS_BASE)
```

### Procedimiento

1. Odin → flashear `new-boot-probe2.img` como `boot.img`.
2. Arrancar; aunque se quede en el logo, apagar.
3. Odin → restaurar `boot.img` rooteado stock.
4. En Android con root:

```bash
adb shell
su
cat /sys/fs/pstore/console-ramoops*
getprop ro.boot.bootcause
getprop ro.boot.restartreason
```

### Interpretación

| Resultado | Conclusión |
|---|---|
| Aparece `XSUB A03FB001 EL=<n>` en pstore | El payload corrió |
| `ro.boot.bootcause` cambia | El payload corrió y tocó el imem |
| Nada cambia | El payload no se ejecutó → problema de firma/offset en LK |

## Causa raíz encontrada: falta el trailer Samsung

El test de control reveló el problema real:

```text
boot.img stock:          67.108.864 bytes (64 MB)
boot.img reconstruido:   24.647.680 bytes
contenido útil (primeros 24.647.680): IDENTICAL
```

El stock añade un trailer a partir de `0x1781800 = 24.647.680`:

```text
0x1781800  "SEANDROIDENFORCE"
0x1781810  "SignerVer02"
...        firma + relleno hasta 64 MB
```

Todos los `new-boot-*.img` anteriores **no tenían ese trailer**, así que LK los rechazaba silenciosamente y se quedaba en el logo de Samsung. Eso explica por qué ningún marcador (UART, framebuffer, RAM, pstore, imem) apareció nunca: **el payload jamás se ejecutó**.

### Verificación del roundtrip

```text
head -c 24647680 boot.img > /tmp/stock-head.bin
python3 add_samsung_trailer.py /tmp/stock-head.bin /tmp/stock-rebuilt.img
cmp /tmp/stock-rebuilt.img boot.img → STOCK_ROUNDTRIP_IDENTICAL
```

El script está en `stub/add_samsung_trailer.py` y coloca la cola del stock exactamente en `0x1781800`.

### Artefacto corregido

```text
D:\a03\new-boot-probe2-full.img   67.108.864 bytes
sha256 = c915cd69a28a9ce6f9dfec57e25eaad9ab8e9a9fe259361833c4ff0264deea41
```

Trailer verificado en `0x1781800`: `SEANDROIDENFORCESignerVer02`.

### Procedimiento

1. Odin → flashear `new-boot-probe2-full.img` como `boot.img`.
2. Arrancar; ahora **sí debería ejecutarse** el payload.
3. Odin → restaurar `boot.img` rooteado stock.
4. En Android con root:

```bash
adb shell
su
cat /sys/fs/pstore/console-ramoops*
```

### Interpretación

| Resultado | Conclusión |
|---|---|
| Aparece `XSUB A03FB001 EL=<n>` | El payload corrió; seguimos con `boot_args` |
| Pantalla blanca/negra | El payload corrió; confirmado por framebuffer |
| Sigue en el logo sin marcadores | El problema es la firma `SignerVer02`, no el trailer |

## Segunda causa encontrada: cabecera ARM64 mal formada

Incluso con el trailer, el payload no corrió. Comparando las cabeceras del kernel stock y el nuestro:

```text
STOCK     code0=0x14480000 code1=0x00000000 text=0x80000 size=0x1AC0000 flags=0xA  magic @0x38="ARMd"
NUESTRO   code0=0x14020000 code1=0xD503201F text=0x80000 size=0x80228  flags=0x0  magic @0x20="ARMd"
```

El error: **nuestro `make_kernel_image.py` puso el magic `"ARMd"` en `0x20` en vez de `0x38`**. La cabecera `arm64_image_header` real es de 64 bytes y el magic va en `0x38`. LK probablemente valida el magic en `0x38` y rechazaba nuestro kernel.

Además, el stock tiene `flags=0xA` y `image_size=0x1AC0000` (23.7MB), mientras el nuestro tenía `flags=0` y solo 524KB.

### Solución: inyectar en el kernel stock

En vez de generar una cabecera desde cero, `stub/inject_payload.py`:

1. Copia el kernel stock entero (23.7MB, cabecera correcta, flags, tamaño).
2. Cambia solo `code0` a `B 0x80000`.
3. Escribe el payload en `0x80000`.

Resultado: LK ve un kernel casi idéntico al stock.

### Artefacto

```text
D:\a03\new-boot-injected.img      67.108.864 bytes
sha256 = 47f9bb54d54d40403380042e5ce30e2cf80e80c9a702e59a465d58e5c11cca66
```

Cabecera verificada (offset 0x800 del boot.img):

```text
code0=0x14020000  code1=0x00000000  text=0x80000  size=0x1AC0000  flags=0xA  magic @0x38="ARMd"
```

También corregí `stub/make_kernel_image.py` para futuros builds (magic en `0x38`).

## Test de control: ramdisk modificado

Para separar "firma del kernel" de "problema de empaquetado", se preparó
`D:\a03\control-ramdisk-mod.img`: kernel stock intacto + ramdisk con `/XNU_PROBE`.

**Resultado (2026-11-21): bucle en el logo Samsung.** Esto **no** demuestra aún que LK rechace
kernels modificados: el ramdisk de ese test estaba mal construido. Nuestro primer `cpio_tool.py`:

- guardaba todos los entries como archivos regulares con mode `0100644`;
- descartaba las entradas de directorio y sus metadata;
- recomprimía todo el CPIO, cambiando tamaño y offsets.

El ramdisk stock tiene 16 entradas, entre ellas `init` con mode `0100750` y los directorios
`.backup`, `dev`, `mnt`, `overlay.d`, `proc`, `sys`. Nuestro ramdisk quedó en 105.077 bytes
contra 745.033 del stock: `init` perdió el bit ejecutable y el arranque entró en bucle.

### Herramienta corregida

`stub/cpio_tool.py` ahora lee y reescribe las entradas newc completas (todos los campos del header,
modo, ino, contenido y orden), y puede insertar una entrada antes de `TRAILER!!!`. Verificado:

```text
init          00100750  184376
.backup       00040000       0
.backup/.magisk 00100000  140
XNU_PROBE     00100644      14   (nueva)
TRAILER!!!    00000755       0
```

### Test `control-ramdisk-concat.img`: ramdisk modificable confirmado

Recomprimir el CPIO completo aumenta el ramdisk 430 bytes y empuja el contenido a pasar de
`0x1781800`, así que se probó un **segundo miembro gzip** de 95 bytes con el CPIO de
`XNU_PROBE`, concatenado al ramdisk stock.

```text
D:\a03\control-ramdisk-concat.img   67.108.864 bytes
sha256 = 62760c96bf08ec59a270fab3b621c43bbb0d0ad329a508193fd0522c6e8df0a0
```

**Resultado (2026-11-21): arrancó a Android y `su` sigue dando contexto `magisk`.** Eso confirma
que LK acepta el ramdisk modificado y que el kernel stock es suficiente para arrancar. Sin
embargo, `/XNU_PROBE` no existe: el kernel 4.14 del A03 no extrajo el segundo miembro gzip.
El cambio sirve como prueba de mutabilidad del ramdisk, pero no como marcador legible.

### Nuevo test: `control-ramdisk-single.img`

Para tener un marcador dentro del único stream gzip, `stub/make_control_ramdisk.py`:

- preserva todas las entradas y permisos del stock;
- quita `.backup/.rmlist` (solo la lista de limpieza de Magisk, innecesaria para el test);
- añade `/X` con contenido `X`;
- reprime el CPIO completo.

Tamaño: 745.441 bytes, por debajo del límite de página 745.472, así que el trailer Samsung
sigue exactamente en `0x1781800`.

```text
D:\a03\control-ramdisk-single.img   67.108.864 bytes
sha256 = 184e7cfc7934df1a725d4e5ddf6802ca3669f2ec4aecb909fae7a5fb5b5da9bf
```

Verificación pendiente:

```sh
adb shell 'cat /X; id'
```

### Test `control-ramdisk-single.img`: marcador no visible

`D:\a03\control-ramdisk-single.img` (sha256 `184e7cfc...`) también arrancó a Android, pero
`cat /X` no encontró el archivo. El entry `X` está correctamente formado dentro del ramdisk del
`boot.img` verificado localmente, así que quedan dos hipótesis: se flasheó otra imagen, o el
parser de initramfs del kernel 4.14 ignora esa entrada nueva.

Para eliminar la segunda hipótesis se preparó `control-ramdisk-existing.img`: no añade entradas,
sino que añade `\nX\n` al contenido de `.backup/.magisk`, un archivo que Magisk lee y que sabemos
que se extrae. Tamaño 745.467 bytes, dentro de la misma página.

```text
D:\a03\control-ramdisk-existing.img   67.108.864 bytes
sha256 = f01c75e14d903132b99cd93ed8df87048527c55adf26edc0fef7fe1cf4d24a51
```

Verificación:

```sh
adb shell 'cat /.backup/.magisk'
```

Debe aparecer `X` al final. Antes de flashear conviene leer el `boot` actual y comparar su hash,
para descartar que se esté probando una imagen distinta.

### Test `control-ramdisk-existing.img`: `.backup` desaparece

`control-ramdisk-existing.img` (sha256 `f01c75e1...`) tampoco permitió ver la marca: Magisk
borra `/.backup` después de restaurar el `/init` original, así que `/.backup/.magisk` no existe
en Android aunque el ramdisk haya sido modificado correctamente. El test era inválido.

### Nuevo test: `control-ramdisk-fstab.img`

Se añade un comentario `# X` al final de `fstab.ums9230_25c10`, un archivo que no se borra y que
sabemos que se lee en cada arranque. No se añaden entradas nuevas y el tamaño sigue dentro de la
misma página (745.466 bytes).

```text
D:\a03\control-ramdisk-fstab.img   67.108.864 bytes
sha256 = 8c884734ea053273b83bb3070f0536d83ba6e3af4ec3b16faee476fa0494605c
```

Verificación:

```sh
adb shell 'grep X /fstab.ums9230_25c10; ls -la / | head -40'
```

Además, antes de flashear conviene leer el `boot` actual y comparar su hash con la imagen que se
cree flasheada, para descartar una confusión entre artefactos.

## Test decisivo del kernel: `cmdline_probe`

Los marcadores dentro del ramdisk no son fiables porque Android/Magisk limpia el rootfs. En cambio,
la modificación del ramdisk ya quedó demostrada: **todas esas imágenes arrancaron a Android**.

Para probar el kernel sin dejar el teléfono colgado, se creó `stub/cmdline_probe.S`:

- entra con `x0 = &boot_args`, MMU off;
- busca el NUL final de `boot_args.CommandLine` (offset `108`);
- añade ` androidboot.xnuprobe=1`;
- salta al entry real del kernel stock.

El entry real se calculó desensamblando `code0 = 0x14480000` con la dirección de carga correcta
(`0x8000`, no `0`):

```text
8000: 14480000  b 0x1208000
```

Es decir, **`0x01208000`**. El cálculo anterior (`0x01200000`) era incorrecto y explica el
bootloop del payload "no-op": saltaba a una dirección inválida. Nuestro payload se inyecta en el
offset `0x80000` del archivo, que se carga en `0x88000`, y solo cambia `code0` a `B 0x80000`.

Artefacto corregido:

```text
D:\a03\kernel-cmdline-probe-boot.img   67.108.864 bytes
sha256 = 5430fcade132a1c27ba271b85dbe0eb3fd6570d239972c42cab86a6850896012
```

Verificación:

```sh
adb shell 'getprop ro.boot.xnuprobe'
```

Si devuelve `1`, significa que:

1. LK acepta un kernel modificado;
2. nuestro código corre en EL1 antes que Linux;
3. el loader estilo iBoot para XNU es viable.

Si no arranca o la propiedad no aparece, hay que revisar si LK valida el kernel o si el salto al
entry real es incorrecto.

### Resultado de `cmdline_probe`: bootloop

`kernel-cmdline-probe-boot.img` entró en bucle y hubo que restaurar el boot stock. Eso todavía no
demuestra una firma: el payload pudo fallar al escribir la cmdline o al saltar. El entry real fue
verificado desensamblando el kernel stock:

```text
1200000: 94000008  bl 0x1200020   ; codigo valido
```

### Test mínimo: `kernel-noop-probe-boot.img`

Para separar "LK rechaza kernel" de "nuestro payload falla", se creó `stub/noop_probe.S`: no toca
ningún byte de `boot_args`, solo salta a `0x01208000` con `x0` intacto. La primera versión usaba
`0x01200000` y por eso entraba en bucle; estaba mal calculada.

```text
D:\a03\kernel-noop-probe-boot.img   67.108.864 bytes
sha256 = 0e89c7f78308399d5b3f419d31cf87f6c12488b46d08e92bf370ededf35bf31a
```

Payload: 16 bytes en `0x80000`, `code0 = B 0x80000`, ramdisk/dtb/cmdline/trailer stock.

## Conclusión retractada: el test del kernel era inválido

Se concluyó prematuramente que LK verificaba el kernel porque incluso el payload `noop` entraba en
bucle. **Esa conclusión era incorrecta.** Al desensamblar el kernel stock:

```text
0:        14480000  b 0x1200000        <- code0: salto relativo a la direccion de carga
1200000:  94000008  bl 0x1200020       <- stext real, en el offset 0x1200000
1200020:  aa0003f5  mov x21, x0        <- x0 = boot_args
120002c:  a9000415  stp x21, x1, [x0]  <- guarda boot_args en 0x1515000
```

En cambio, el offset `0x80000`, donde inyectábamos el payload, contiene código vivo:

```text
80000: 54ffff21  b.ne 0x7ffe4
80020: 97fffee9  bl 0x7fbc4
```

Es decir, **estábamos sobrescribiendo una función real del kernel**. Eso explica el bootloop aunque
el payload no hiciera más que un salto. Además, el valor `0x01208000` venía de un
`--adjust-vma=0x8000` de objdump: era un artefacto de visualización, no una dirección real.

Por tanto, el bootloop **no demuestra** que LK rechace kernels modificados, y la firma de Samsung
sigue sin ser el bloqueo confirmado. Hay que repetir el test sin tocar ni un byte del código.

## Resultado: LK ACEPTA kernels modificados

`kernel-noop-probe2-boot.img` **arrancó a Android**. Payload de 20 bytes al final del archivo
(`0x169e810`), `code0 = b 0x169e810`, sin sobrescribir código del stock:

```text
sha256 = a5e7ce421ead1542af8f128ee292252a091e86a45551a38267771f25a0323eff
```

Conclusión: no hace falta firmar, ni tocar vbmeta. La firma `SignerVer02` no bloqueó la imagen
modificada (o LK no la verifica en este estado). El bloqueo anterior era nuestro payload corrupto.

Estado de AVB leído del teléfono (informativo, ya no es crítico):

```text
ro.boot.flash.locked = 0
ro.boot.vbmeta.device_state = unlocked
ro.boot.verifiedbootstate = orange
ro.boot.veritymode = enforcing
```

## kexec descartado; módulos de kernel como alternativa

Comprobado en el boot rooteado stock:

```text
cat: /proc/sys/kernel/kexec_load_disabled: No such file or directory
# CONFIG_KEXEC is not set
CONFIG_MODULES=y
CONFIG_MODULES_USE_ELF_RELA=y
CONFIG_MODULES_TREE_LOOKUP=y
```

No hay kexec. Sin embargo, `CONFIG_MODULES=y` abre otra vía: un módulo cargado con `insmod`
ejecuta su `module_init` en **EL1**, con el kernel stock ya arrancado y confiable para LK.

Comprobado en el teléfono:

```text
# CONFIG_MODULE_SIG is not set
```

Es decir, **se pueden cargar módulos sin firma**. Es una vía válida para ejecutar código en EL1,
aunque más tardía que parchear el `boot.img`. La ruta principal sigue siendo el payload inyectado.

## Sobre parchear vbmeta

La idea es razonable: en muchos dispositivos, poner los flags de `vbmeta` en
`AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED | VERIFICATION_DISABLED` permite arrancar un `boot.img`
modificado, kernel incluido. Pero en este A03 hay dos razones para no darla por ganada:

1. **No hemos verificado el estado real de AVB en el teléfono.** El cmdline del `boot.img` solo
   contiene `console=ttyS1,115200n8`; las propiedades `androidboot.verifiedbootstate=...` y
   `androidboot.vbmeta.*` no están en ese cmdline, las genera el bootloader. Hay que leerlas:

   ```sh
   adb shell 'getprop | grep -iE "verifiedboot|vbmeta|verity|flash.locked|bootstate"'
   adb shell 'ls -l /dev/block/by-name/ | grep -i vbmeta'
   ```

2. Samsung usa además su propia firma `SignerVer02`/`SEANDROIDENFORCE` en el `boot.img`, que es
   independiente de AVB. Incluso con AVB desactivado podría seguir aplicando. Eso sí: como el test
   del kernel era inválido (sección anterior), **todavía no sabemos si esa firma está bloqueando**.

Parchear vbmeta implica flashear otra partición (con riesgo de Knox) y no conviene hacerlo hasta
haber repetido correctamente el test del kernel modificado. Se deja como hipótesis, no como causa
confirmada.

## Cadena correcta para `/proc/version`

El primer `version_probe` no mostró cambio porque parcheó la cadena equivocada. En el kernel hay
dos cadenas distintas:

```text
0x1062248  "Linux version 4.14.199..."   -> linux_banner (solo dmesg)
0x10623a0  "%s version %s (dpi@...)"     -> linux_proc_banner (/proc/version)
```

El control `kernel-string-only2-boot.img` (ambas cadenas parcheadas, `code0` intacto):

```text
sha256 = 4f7f1ae3c62c3d8519528ec28a960a9647892008749f95d859d6dbe3bb0155a1
```

Arrancó y `/proc/version` mostró:

```text
XN version Linux (dpi@SWDK6902) ...
```

**Confirmado:** el kernel flasheado es el nuestro y el offset `0x10623a0` es correcto.

## Ejecución real en EL1: CONFIRMADA

`stub/version_probe3.S` parchea `linux_proc_banner` **desde nuestro payload**:

1. calcula `image_base = PC_actual - 0x169e810`;
2. cambia `"%s"` por `"XZ"` en `0x10623a0`;
3. salta a `stext` (`image_base + 0x1200000`) con `x0` intacto.

```text
D:\a03\kernel-version-probe3-boot.img
sha256 = 44f51019a5f3733114433bed37f8cad6b384072a2da014a8131229aa9dc22d5a
```

Resultado en el teléfono:

```text
XZ version Linux (dpi@SWDK6902) ...
```

**Marcador único `XZ`: nuestro código corre en EL1 antes que Linux.** No hace falta firma, vbmeta,
kexec ni módulos. LK ejecuta `code0` y salta a nuestro payload.

Esto explica también por qué fallaron los marcadores anteriores de framebuffer/pstore: el payload
nunca se estaba ejecutando porque se inyectaba en `0x80000` (código vivo) o no se alcanzaba.

`/proc/version` es ahora un **canal de debug**: podemos escribir un string desde el payload y leerlo
desde Android después del arranque.

## Loader de `boot_args` (fase 1)

`stub/bootargs_loader.S` construye `struct boot_args` en `0x92000000`:

- `Revision = Version = 2` (`kBootArgsRevision2`, `kBootArgsVersion2`, fuente: `boot.h`).
- `virtBase = 0xfffffff007004000` (`VM_KERNEL_LINK_ADDRESS`, fuente: `MakeInc.def`).
- `physBase = 0x80000000`, `memSize = memSizeActual = 0xfffff000` (DTB del A03).
- `CommandLine = "debug=0x8 kext-dev-mode=1"`.
- `deviceTreeP = x0` (el FDT que ya cargó LK), `deviceTreeLength` leído del header FDT con `rev`.

No se incrusta el DTB: entre el contenido stock y el trailer Samsung solo quedan ~5 KB libres.

El payload calcula un checksum de los campos fijos y lo escribe en `linux_proc_banner`, seguido de
`D` si el magic de `x0` es `0xD00DFEED` o `X` si no:

```text
D:\a03\kernel-bootargs-loader-boot.img
sha256 = 387a3942d208fe9761d508052f51eff456a9aa30e6513344112fb8248c5b660b
esperado: BA:47fafc25a0c53650:D
```

Verificación:

```sh
adb shell 'cat /proc/version'
```

Resultado obtenido:

```text
BA:47fafc25a0c53650D
```

Checksum idéntico al esperado y marcador `D`: **`x0` es el FDT y `boot_args` quedó bien
construido**. (El `:` del string esperado no se imprime; el formato real es `BA:<16 hex><D|X>`.)

## Handoff estilo `_start`: `xnu_entry_probe`

`stub/xnu_entry_probe.S` añade una segunda fase que simula el entry de XNU:

- recibe `x0 = &boot_args` (`0x92000000`);
- valida `Revision/Version = 2/2` y que `deviceTreeP` apunte a un FDT con magic `0xD00DFEED`;
- escribe `:XNUOK` o `:XNUBAD` en `/proc/version`;
- restaura `x0 = FDT` y vuelve al kernel stock.

```text
D:\a03\kernel-xnu-entry-probe-boot.img
sha256 = a9cb80f33f0e7673c5467310f1a41e6cc5c35bb9248335c58cb21bda924a70df
esperado: BA:47fafc25a0c53650D:XNUOK
```

Verificación:

```sh
adb shell 'cat /proc/version'
```

Resultado obtenido:

```text
BA:47fafc25a0c53650D:XNUOK
```

**Cadena de handoff completa y validada:** payload → `boot_args` (`0x92000000`) → fase B estilo
`_start` (`x0 = &boot_args`, `Revision/Version = 2/2`, `deviceTreeP` con magic `0xD00DFEED`) →
retorno seguro a Linux. Ya no queda nada por validar en el bootloader.

## Cargador de blob + UART

`stub/blob_loader.S` extiende el loader con el último eslabón que faltaba:

1. construye `boot_args` en `0x92000000` (igual que antes);
2. copia un blob desde el final del kernel Linux a **`0x92500000`**
   (zona libre del DTB: `boot_args` en `0x92000000`, `uboot_log` en `0x92400000`,
   `audio-mem` en `0x94100000`, `initrd` en `0xa0000000`);
3. ejecuta `ic iallu; dsb sy; isb sy` antes de saltar;
4. salta al blob copiado con:

```text
x0 = &boot_args (0x92000000)
x1 = image_base del kernel Linux
x2 = stext del kernel Linux (retorno)
x22 = FDT
```

`stub/blob_kernel.S` es un kernel sintético enlazado en `0x92500000`. Valida los campos, imprime
el PC real de ejecución y devuelve el control a `stext` con `x0 = FDT`, así que Android arranca con
normalidad.

```text
D:\a03\kernel-blob-loader-boot.img
sha256 = 4238c4e723d60cedbb66356604b1447d6b854fad228c741c547d5df707c549c6
loader : 288 bytes @ 0x169e810
blob   : 365 bytes @ payload+0x120 -> 0x92500000
```

Verificación:

```sh
adb shell 'cat /proc/version'
```

Resultado esperado:

```text
BL:47fafc25a0c53650:0000000092500000
```

- El checksum coincides con el de `boot_args`.
- El PC `0000000092500000` demuestra que el código corre **después de la copia a RAM**, no en el
  origen dentro del kernel Linux.
- Por la UART de consola (`serial1`, `0x200b0000`, 115200 8N1) debe aparecer:

```text
A03-BLOB-KERNEL-OK pc=0x92500000
```

El debug por serie usa los registros SPRD ya documentados en `stub/uart_regs.h` y no reinicializa
el baud, porque LK ya dejó la UART configurada.

### Resultado: cuelgue en el logo de Samsung

`kernel-blob-loader-boot.img` **no arranca**: se queda en el logo de Samsung. No hay UART en el
dispositivo de prueba, así que el único síntoma es el logo. Esto sitúa el fallo dentro de nuestro
payload (que corre desde `code0`, antes de `stext`).

Sospechoso principal: el bucle de `putc` esperaba a que `SPRD_STS1` indicara TX vacío. Si el
periférico no es accesible en ese instante, el registro lee `0xFFFFFFFF` y el bucle nunca termina.
Los payloads anteriores (`version_probe3`, `xnu_entry_probe`) **no tocaban la UART**, por lo que
nunca se había comprobado este supuesto.

### Intento 2: UART no bloqueante + coherencia reforzada

`kernel-blob-loader2-boot.img`:

```text
sha256 = 8381c116ea68fa71cc8422d293db4448e5b19e180332c6252c704e5b8dc3518e
```

Cambios:

- `putc` tiene una espera **limitada** (256 iteraciones); si la UART no responde, se ignora el byte
  y se continúa. Ya no puede colgar el arranque.
- El loader hace `dc civac` sobre el destino antes de `ic iallu; dsb sy; isb sy`.

### Intento 3 (respaldo): blob mínimo

`kernel-blob-min-boot.img`:

```text
sha256 = 93736d73959d8d88d638adeb50ed733bed987bbf1cd3a493a1b397ba134b4414
```

Usa el **mismo loader** del intento 2, pero el blob de 8 bytes solo hace `mov x0, x22; br x21`
(volver a Linux). No escribe `/proc/version` ni UART.

- Si el intento 2 arranca → el culpable era el código UART del blob.
- Si el intento 3 arranca pero el 2 no → el culpable es el cuerpo del blob (escritura en
  `linux_proc_banner` o UART).
### Resultado de los intentos 2 y 3

- Intento 2 (`kernel-blob-loader2-boot.img`): **sigue colgado en el logo**.
- Intento 3 (`kernel-blob-min-boot.img`): **se reinicia**.

El intento 3 tenía un bug propio: el blob mínimo hacía `br x21`, pero el loader pasa `stext` en
`x2` (`x21` contiene basura). Eso explica el reinicio y **descarta la UART** como causa del
intento 2.

Quedan dos sospechosos: las instrucciones de caché (`dc civac`/`ic iallu`) o la copia/salto a
`0x92500000` en sí.

### Intento 4: sin instrucciones de caché

`kernel-blob-min2-boot.img` — loader sin `dc civac`/`ic iallu`, blob mínimo corregido (`br x2`):

```text
sha256 = 2d084faa8afd2108dae43f5da155e7cc530800da5f405ff7d03a936420b68cb5
```

`kernel-blob-nocache-boot.img` — mismo loader, blob completo (checksum + `/proc/version` + UART
no bloqueante):

```text
sha256 = 64ace3ae57574fec1f63e1f5e7090380fcf3b69a2b73451f0d1a6e409f7c3444
```

Probar primero el mínimo:

- Si arranca el mínimo → las instrucciones de caché eran el problema; probar entonces el completo.
- Si el mínimo también falla → probar otro destino (`0x91000000`, documentado como libre en
  `stub/link.ld`) o volver a saltar a código enlazado dentro del propio payload.

### Resultado y cambio de estrategia

- `kernel-blob-min2-boot.img` (sin caché, blob mínimo corregido): **se reinicia**.
- `kernel-blob-nocache-boot.img` (sin caché, blob completo): **se queda en el logo**.

Con los cuatro intentos, la copia a `0x92500000` + salto queda descartada. En cambio, el esquema de
`xnu_entry_probe` (ejecutar código **dentro del propio payload**, sin copiar) sí arrancó. El usuario
no dispone de UART, así que el debug se traslada al framebuffer.

## Framebuffer como UART

`stub/fb_console.S` vuelve al esquema que funciona y usa el framebuffer del logo como consola:

- borra `0x9E000000` (`lcd_base` del DTB, 1600×720×24bpp, 3.456.000 bytes);
- fuente bitmap 5×7 escalada 3× (caracteres de 15×21 píxeles, ~106 columnas por línea);
- imprime:

```text
XNU A03 FB UART
BA CK 47fafc25a0c53650
PC 000000000169e810
FDT D
RET OK
```

- escribe además `FB:<checksum>:D` en `linux_proc_banner` como canal secundario;
- vuelve a `stext` con `x0 = FDT`.

```text
D:\a03\kernel-fb-console-boot.img
sha256 = 5473dddc42ceecb601021cacf49941352080b59741260619a3ad717eb2a1e52b
payload = 1092 bytes @ 0x169e810
```

Si aparece el texto en pantalla, el framebuffer queda validado como canal de debug y puede
sustituir a la UART en los siguientes payloads (incluido el salto final a XNU).

### Resultado: pantalla blanca, sin texto

`kernel-fb-console-boot.img` **sí alteró la pantalla** (el logo desapareció y apareció un fondo
blanco/gris claro), pero **no se dibujó ningún texto**. El análisis de la foto
(`D:\a03-apple\20261122_151910.jpg`) muestra colores dominantes `bbd2da`/`b6ccd7` en el centro y
tonos marrones en los bordes, sin patrón de caracteres.

El DTB confirma dos regiones candidatas:

- cmdline: `lcd_base=9e000000 lcd_size=1600x720 logo_bpix=24`
- reserva: `fb_reserved = "/reserved-memory/framebuffer-mem@fd380000"`

El payload escribió solo en `0x9E000000`. Como no apareció nada legible, hay que determinar cuál de
las dos direcciones está realmente activa y en qué orden de canales.

### Sonda de color: las dos regiones a la vez

`stub/fb_probe.S` pinta 4 bandas de 180 filas en cada región y se detiene:

| `0x9E000000` | `0xFD380000` |
|---|---|
| rojo | negro |
| verde | amarillo |
| azul | cian |
| blanco | magenta |

```text
D:\a03\kernel-fb-probe-boot.img
sha256 = 017f1683af66662b8d17bc580c0ff00d892386eb556b2154061614bf0578a245
payload = 280 bytes @ 0x169e810
```

- Si aparecen rojo/verde/azul/blanco → `0x9E000000` es el activo.
- Si aparecen negro/amarillo/cian/magenta → `0xFD380000` es el activo.
- Si el "rojo" se ve azul → el formato es BGR en vez de RGB.

**Resultado:** apareció **solo la banda blanca**. Ambiguo: puede ser un recorte del buffer, un
stride distinto o que las dos regiones sean alias.

### Sonda 2: división vertical vs. horizontal

`stub/fb_probe2.S` usa una división inequívoca:

- `0x9E000000`: mitad izquierda **roja**, mitad derecha **verde** (división vertical).
- `0xFD380000`: mitad superior **azul**, mitad inferior **amarilla** (división horizontal).

```text
D:\a03\kernel-fb-probe2-boot.img
sha256 = 66e531a397786a1c42eaefe8fc4b6afbe71ddb6e06d18faf6186ab3b69d636cb
payload = 168 bytes @ 0x169e810
```

- División vertical → `0x9E000000`.
- División horizontal → `0xFD380000`.
- Un solo color → las regiones son alias o el formato no es 24bpp; haría falta leer el stride real
  desde el DTB (`sprd,dpu-layer` / `fb_reserved`) y probar 16bpp/32bpp.

**Resultado de la sonda 2:** la foto (`20261122_152839.jpg`) muestra un rectángulo gris-azulado
uniforme, sin división vertical ni horizontal. El análisis de cuadrantes confirma diferencias de
solo ~10-20 unidades (iluminación de la foto), no los colores puros esperados (0/255).

### Dato clave del DTB

```text
dpu@31000000:
  sprd,logo-memory = <0x1c7>          -> logobuffer@9e000000, tamaño 0xab0000
  iommus = <0x27>                     -> iommu@31000000
  spd,iova-base = <0x30000000>, iova-size = <0x10000000>
  dma-coherent
fb_reserved -> framebuffer-mem@fd380000, tamaño 0x1300000
```

El DPU accede a la memoria a través de **IOMMU**: la dirección que usa el hardware (`IOVA`, entorno
`0x30000000`) no tiene por qué coincidir con la física (`0x9E000000`). Escribir en la PA correcta
puede no cambiar lo que escanea el DPU si el mapeo IOVA→PA no es identidad.

### Sonda de etapas por /proc/version

Para separar "nuestro código no corre" de "el DPU no muestra", `stub/fb_stage_probe.S` escribe
marcadores en `linux_proc_banner` antes/después de cada llenado y vuelve a Linux:

```text
D:\a03\kernel-fb-stage-boot.img
sha256 = ef6eb3b45b484d0d0a392086f56c04cf0431128342eee143ca36d53e55924f34
```

Lee con `adb shell 'cat /proc/version'`:

| Valor | Significado |
|---|---|
| `100` | entró al payload, pero se colgó llenando `0x9E000000` |
| `120` | llenó `0x9E000000`, se colgó llenando `0xFD380000` |
| `123` | ambos llenados completos → el problema es DPU/IOMMU/panel, no el código |

**Resultado:** `123`. Ambos llenados se completan; el fallo está aguas abajo de la CPU.

### Sonda con limpieza de caché

Al entrar desde LK, la MMU/caché pueden seguir activas. Los `strb` del payload pueden quedar en
L1/L2 y no llegar a DRAM, mientras el DPU lee por DMA la imagen antigua. `fb_cache_probe.S` limpia
la caché (`dc cvac`, 54000 líneas de 64 bytes por región, `dsb sy`) después de escribir:

- `0x9E000000`: 4 bandas horizontales (rojo / verde / azul / blanco).
- `0xFD380000`: magenta sólido.

```text
D:\a03\kernel-fb-cache-boot.img
sha256 = bd94ada035e79ab8654415535a4d5d98422fb0797e25e1595fe309d66f5b1b87
```

- Si aparecen bandas → `0x9E000000` es el activo y faltaba la limpieza de caché.
- Si aparece magenta → `0xFD380000` es el activo.
- Si sigue igual → el DPU no escanea ninguna de las dos; quada por investigar la IOVA del IOMMU
  (`sprd,iova-base=0x30000000`) o inspeccionar los registros del DPU en `0x31000000`.

**Resultado:** la foto (`20261122_153702.jpg`) sigue mostrando el mismo gris-azulado uniforme, pero
más claro. La pista decisiva es el intento anterior: con 24bpp, **solo aparecía la banda blanca**.
Eso encaja con un framebuffer **ARGB8888 de 32bpp**: al escribir 3 bytes por píxel, el 4º byte
(alfa) queda en 0 → transparente → se ve el fondo; la banda blanca (`FF FF FF FF`) es la única
opaca.

### Sonda 32bpp con alfa=0xFF

`stub/fb_probe32.S` escribe píxeles de 4 bytes (1600×720×4 = 4.608.000 bytes, stride 6400) con
alfa 0xFF y 4 bandas horizontales: rojo / verde / azul / blanco. Incluye `dc cvac`.

```text
D:\a03\kernel-fb-probe32-boot.img
sha256 = b6cfe5a068fa2cd9d1ba8e3b2d0cfcc04ea1f789f71df51db0492ec903eb4cff
```

Si aparecen las 4 bandas, el framebuffer queda calibrado: 32bpp, `0x9E000000`, little-endian.
Entonces `fb_console.S` se reescribe con píxeles de 4 bytes y la fuente escalada en consecuencia.

**Resultado:** aparecieron los 4 colores. Framebuffer calibrado: **`0x9E000000`, 1600×720,
32bpp ARGB8888 little-endian, alfa=0xFF, `dc cvac` obligatorio**.

### fb_console calibrado

`stub/fb_console.S` reescrito con:

- píxeles de 4 bytes (B,G,R,A=0xFF) y stride 6400;
- borrado de 4.608.000 bytes (288.000 `stp`);
- fuente 5×7 escalada 3× con alfa opaco;
- `dc cvac` sobre 72.000 líneas de caché antes de volver;
- fix: `fb_print_hex64` usa `x28` como contador (antes usaba `x16`, que `fb_putc` destruye);
- `/proc/version` como canal secundario.

```text
D:\a03\kernel-fb-console-boot.img
sha256 = 0a03f03a39cd39d04f2c361fba5600415eb198192d7c7aeb5bf25a4cfc46f024
payload = 1124 bytes @ 0x169e810
```

Debe mostrar en pantalla:

```text
XNU A03 FB UART
BA CK 47fafc25a0c53650
PC 000000000169e810
FDT D
RET OK
```

y en `/proc/version`: `FB:47fafc25a0c53650D`. Con esto el framebuffer sustituye a la UART como
consola de debug para el salto final a XNU.

### Resultado: texto distorsionado / fondo claro

La foto (`20261122_154259.jpg`) mostraba el fondo gris-azulado del logo, no negro. Causa: el
borrado escribía `0` en los 4 bytes, y en ARGB8888 eso es **alfa=0 (transparente)**: el DPU
componía el logo debajo del texto. El texto blanco sobre fondo claro apenas se distinguía y la
fuente 3× sin separación pegaba los caracteres.

Correcciones en `fb_console.S`:

- borrado a **negro opaco**: `0xFF000000` por píxel (B=0,G=0,R=0,A=0xFF), 1.152.000 `str`;
- escala **4×** con celda de 24×32 px (1 columna/fila de separación entre caracteres);
- máximo 64 caracteres por línea (1600/24).

```text
D:\a03\kernel-fb-console-boot.img
sha256 = 6989ecf9ff759b94c5ad89e19ca35003e8054132d0f322ff9060e901a84c6fdc
```

Debe verse ahora texto blanco nítido sobre fondo negro.

**Resultado:** el texto sigue distorsionado. Sin foto no se puede distinguir entre rotación 90°,
skew por stride distinto o solapamiento de caracteres. Se preparó una sonda de geometría:

```text
D:\a03\kernel-fb-grid-boot.img
sha256 = 5bc7a0fc8eb3218c80300a727506cd557881d67c850d1233cb7df5a8431d2d01
```

Dibuja 4 cuadrados de 100×100 en las esquinas (rojo sup-izq, verde sup-der, azul inf-izq,
amarillo inf-der) y una rejilla cada 200 px:

- si los 4 cuadrados forman un rectángulo → stride 6400 correcto, el problema es la fuente;
- si están sesgados → stride distinto;
- si el rectángulo aparece girado 90° → el panel rota y hay que trasponer las coordenadas.

**Resultado:** solo se dibujó el rojo. Bug en `rect`: modificaba `x1` (sy) dentro del bucle, así que
la segunda llamada recibía una y ya incrementada y los cuadrados salían fuera de pantalla. Corregido
con temporales `x5`..`x9` separados de los parámetros:

```text
D:\a03\kernel-fb-grid-boot.img
sha256 = db5b648957632a680101c313916cc3288903efb6d06fe28887328ec94d98154e
```

**Resultado:** solo se dibujó el rojo. Causa raíz: en AArch64 `bl` escribe la dirección de retorno
en `x30`. `rect` llama a `px` con `bl`, sobrescribiendo su propio `lr`; al hacer `ret` saltaba al
interior de su bucle en vez de volver a `_start`. Corregido guardando `x30` en la pila
(`str x30, [sp,#-16]!` / `ldr x30, [sp],#16`):

```text
D:\a03\kernel-fb-grid-boot.img
sha256 = 4e3f54f8523dc1d4b76825a136039788e51d4cf9f0b0cdcab1b3650c05a9773d
```

El mismo bug estaba en `fb_console.S`: `fb_putc` → `fb_pixel` y `fb_print_str`/`fb_print_hex64` →
`fb_putc` sobrescribían `x30`, causando el texto distorsionado. Corregido en las 3 funciones.
Además se preservó el FDT en `x20` antes de la limpieza de caché (x22 se sobrescribía y se pasaba
la dirección del framebuffer al kernel en lugar del DTB):

```text
D:\a03\kernel-fb-console-boot.img
sha256 = e28292376260ea8f09e4fe7b62a805adaf197cbb5caec53827e9af67f1e4b52b
```

**Resultado:** el texto sigue viéndose distorsionado, pero el análisis de las fotos
(`20261122_155459.jpg`, `20261122_155558.jpg`) muestra bloques de texto mezclados con otros
patrones, no glifos mal formados. Hipótesis: `fb_console.S` vuelve a `stext`, Linux sigue arrancando
y redibuja el logo/animación sobre `0x9E000000`, sobrescribiendo parte del texto. Las sondas de color
que funcionaron terminaban en `wfe` (imagen congelada).

### Prueba decisiva: consola congelada

`fb_console_hang.S` = `fb_console.S` pero termina en `wfe` en vez de volver a `stext`:

```text
D:\a03\kernel-fb-console-hang-boot.img
sha256 = 4c133145dd7e78ce5b3f86e5e853b2d4d0816709e928b6636a8e067f7c8f82a9
```

- Si el texto se ve nítido → la distorsión era el redibujado de Linux; la consola es correcta y para
  el salto final a XNU (que no redibuja) no habrá problema.
- Si sigue distorsionado → el problema está en la fuente/geometría de `fb_console.S`.

**Resultado:** sigue distorsionado incluso congelado → descartado el redibujado de Linux. Revisando
`fb_pixel` aparece el bug real: `FB_STRIDE` era `6400` (bytes por fila) y se volvía a multiplicar
por 4 (`y * 6400 * 4` en vez de `y * 1600 * 4`), duplicando el paso vertical. Corregido:
`FB_STRIDE = 1600` píxeles por fila.

```text
D:\a03\kernel-fb-console-hang-boot.img
sha256 = 7875b29237080fcac3fcebab996b53f872b506d6c5734eb932a75ec9ede4d857

D:\a03\kernel-fb-console-boot.img
sha256 = f5795a684f292eacd7d457bbb3e6558360c238a03702e80b23a6dad74478ce3c
```

La imagen `hang` congela el texto para validarlo; la otra vuelve a Linux para comprobar
`/proc/version`.

**Resultado:** con `kernel-fb-console-hang-boot.img` (`7875b292`) y stride corregido, el texto sale
**aplastado / superpuesto**. Como la imagen está congelada, no es el redibujado de Linux: el fallo
está en el renderizado de la fuente.

### Sonda de barras (aislar geometría de fuente)

`fb_bars.S` dibuja 3 barras blancas horizontales (x=50..549) en y=50, 150 y 250, sin fuente y sin
llamadas anidadas salvo `draw_bar`:

```text
D:\a03\kernel-fb-bars-boot.img
sha256 = 7b55ea8584e6d9c748cbcffaff8198b44b77f6dde032f5585b4d130846d8c89f
```

- Si las 3 barras aparecen separadas y a igual distancia → stride/geometría correctos; el bug está
  en `fb_putc` (fuente) y se reescribe.
- Si salen juntas o aplastadas → el bug está en el cálculo de Y / stride.

**Resultado:** las barras salen juntas/aplastadas. El cálculo `(y * 1600 + x) * 4` está mal,
a pesar de que las sondas de color (que escribían secuencialmente) funcionaron. Eso indica que el
stride real NO es 1600 píxeles.

### Detector de stride

`fb_stride_detector.S` escribe secuencialmente (método probado) un patrón de 6 filas de colores
(rojo, verde, azul, amarillo, blanco, negro) repetido 20 veces. Cada «fila» = 6400 bytes.

```text
D:\a03\kernel-fb-stride-detector-boot.img
sha256 = e753a1bd247f8172cdaf2f3dd0486c9f883ce70bcfef2ff9058f8db20f8a4d66
```

- Si las franjas salen **horizontales** → stride = 6400 bytes (1600 pixeles) y el bug está en otra
  parte del cálculo de direcciones.
- Si salen **diagonales** → el stride real es distinto; se mide el desplazamiento entre franjas
  para calcularlo.
- Si salen **verticales** → el panel rota 90° y el framebuffer es 720×1600.

**Resultado:** franjas **horizontales**. Confirmado: el formato es 32bpp, 1600 px/fila, 6400 bytes/fila,
escritura secuencial desde `0x9E000000`. El stride era correcto; el fallo estaba en el código que
calculaba direcciones con `mul` y en conflictos de registros.

### Consola con escritura secuencial

`fb_console_seq.S` reescribe la consola usando **exactamente** el método probado: recorre la pantalla
fila por fila y escribe cada píxel secuencialmente, sin calcular direcciones. Determina el color de
cada píxel a partir de la fuente 5×7 con `udiv`, evitando `mul` para direcciones.

Bug corregido durante la escritura: el puntero del framebuffer estaba en `x2`, pero `get_char` y
`glyph_bit` lo sobrescribían → se movió a `x8`.

```text
D:\a03\kernel-fb-console-seq-boot.img
sha256 = 8f6c29cbbbe89d4fecdd38a80ca67dbfda749cc7675e9b18282689b51f96245b
```

Debe mostrar 3 líneas:

```text
XNU A03 FB UART
BA CK 0123456789ABC
RET OK
```

Congela la imagen al final (`wfe`). Si sale legible, se integra con `boot_args` y `/proc/version`.

### Variante con ancho 720 (propuesta del usuario)

**Resultado:** el texto sigue distorsionado con 1600 px/fila. El panel físico del A03 es 720×1600
(vertical), así que el buffer en memoria puede estar organizado como 720 px/fila (2880 bytes/fila),
no 1600. `fb_console_seq720.S` usa `ROW_PX = 720` y 30 caracteres por línea:

```text
D:\a03\kernel-fb-console-seq720-boot.img
sha256 = c3387296e3c5a6ec7c79129b75495c614b0bd03829172eba2c825a3bd764d615
```

Si el texto se ve legible, el framebuffer real es 720×1600 y hay que invertir la lógica de
coordenadas en todas las sondas futuras.

**Resultado: LEGIBLE Y CORRECTO.** Confirmado por el usuario. Configuración definitiva del
framebuffer del A03:

```text
base   = 0x9E000000
ancho  = 720 pixeles/fila  (2880 bytes/fila)
alto   = 1600 filas
total  = 1152000 pixeles = 4608000 bytes
formato= 32bpp BGRA little-endian (A=0xFF)
metodo = escritura secuencial + dc cvac
```

El cmdline `lcd_size=1600x720` es la resolución del panel, no el layout del buffer.

### Consola definitiva

`fb_console_final.S` integra la geometría calibrada con `boot_args`, `/proc/version` y retorno a
`stext`. El FDT se preserva en la pila porque `x22` se sobrescribe durante la limpieza de caché.

```text
D:\a03\kernel-fb-console-final-boot.img
sha256 = 03e70666b4c3a3ead5a7ffe438d01553f25c2f9c7e907ac6e3a969786b991b61
payload = 1036 bytes @ 0x169e810
```

Debe mostrar en pantalla las 3 líneas calibradas y en `/proc/version`: `FB:<checksum>:D`.
Con esto el framebuffer sustituye a la UART como consola de debug.

**Resultado: bootloop.** Causa: `x24` guarda `image_base`, pero el bucle de dibujo lo sobrescribía
con la fila de caracter (`udiv x24, x24, #32`). Al final `add x2, x24, x2` saltaba a una dirección
inválida. Corregido moviendo la fila de caracter a `x6`:

```text
D:\a03\kernel-fb-console-final-boot.img
sha256 = 75c65ae40dd9495b817b5d07b7b301cf1221ccff38b0921d36e91671fcb2adc7
```

**Resultado:** verificado por el usuario con `cat /proc/version`:

```text
FB:47fafc26260af341D
```

Canal secundario funcionando: prefijo `FB:`, checksum de `boot_args` `47fafc26260af341`, y `D`
(FDT con magic `0xEDFE0DD0`). Android arranca completo. El boot.img rooteado stock ya fue restaurado.

## Payload integrado: framebuffer + handoff XNU

`xnu_fb_handoff.S` integra los dos canales validados por separado:

- consola framebuffer calibrada (720×1600, escritura secuencial, `dc cvac`);
- `boot_args` + `/proc/version` (`FB:<ck>:D`);
- handoff estilo `_start`: `x0 = &boot_args`, salto a `xnu_entry`, validación `:XNUOK`/`:XNUBAD`;
- indicador visual: franja **verde** en y=96..127 si el handoff es válido, **roja** si falla.

Cambios de registros respecto a `fb_console_final.S` para evitar otro bootloop:

- la coordenada Y del bucle de dibujo pasó de `x19` a `x17` (libre), para preservar
  `x19 = &boot_args` hasta el handoff;
- las etiquetas numéricas de `xnu_entry` usan 50..57 para no colisionar con `get_char` (30..32)
  ni `glyph_bit` (40..41).

```text
D:\a03\kernel-xnu-fb-handoff-boot.img
sha256 = 17299203fa7f38185e3e7ea9bd436a223a52e38afc865562c4c83b6e2d52ecf5
payload = 1291 bytes @ 0x169e810
```

Salida esperada:

```text
pantalla: 3 líneas de texto + franja VERDE
/proc/version: FB:47fafc26260af341D:XNUOK
```

**Aclaración:** `xnu_entry` es una sonda que simula el contrato de `_start` de XNU. Todavía no
existe kernelcache propio para T606; esto **no** arranca XNU real.

**Resultado: ÉXITO.** Confirmado por el usuario con la imagen `17299203...`:

```text
pantalla: 3 líneas legibles + franja VERDE en y=96..127
/proc/version: FB:47fafc26260af341D:XNUOK
```

## Loader de fase 2 desde el ramdisk

Para cargar un XNU real (20-30 MB) no cabe en los ~925 KB libres antes del trailer Samsung. La
estrategia elegida: el payload inyectado en el kernel actúa como **loader** y lee un blob desde el
CPIO del ramdisk, que LK ya descomprime a `0xA0000000` y acepta modificado.

Archivos nuevos:

| Archivo | Función |
|---|---|
| `stub/rd_loader_entry.S` | calcula `image_base` desde el PC, guarda el FDT, llama al loader en C |
| `stub/rd_loader.c` | busca `xnu_payload.bin` en el CPIO newc, copia a `0xA1000000`, `dc civac` + `ic ivau` + `isb`, devuelve el entry |
| `stub/rd_test_blob.S` | blob de prueba: marca `RL:OK` en `/proc/version` y dibuja franja azul en y=128..159 |
| `stub/Makefile.loader` | compila loader + blob sin libc (`-ffreestanding -fno-builtin`) |
| `stub/make_rd_ramdisk.py` | añade el blob al CPIO y elimina `.backup/init.xz` (backup de Magisk, 491 KB) para que quepa en la misma página |
| `stub/build_rd_loader.sh` | pipeline completo |

Notas de implementación:

- El CPIO newc se escanea desde `0xA0000000` buscando la magia `070701`; se comprueban los campos
  `filesize` (offset `6 + 7*8`) y `namesize` (offset `6 + 12*8`).
- Destino de carga: `0xA1000000`, por encima del initrd (`0xA0000000..0xA00CA000`).
- Coherencia: `dc civac` sobre el destino, `dsb sy`, `ic ivau`, `dsb sy`, `isb sy`. La sonda anterior
  (`blob_loader.S`) usaba solo `ic iallu` y saltaba a `0x92500000`; fue descartada.
- Si el blob no se encuentra o el tamaño es inválido, el loader devuelve 0 y el entry vuelve a
  `stext`, así que Android arranca y se puede leer el marcador.

Marcadores en `/proc/version`: `RL:0` entró, `RL:1` encontrado, `RL:3` copiado, `RL:4` va a saltar,
`RL:F` no encontrado. El blob de prueba sobrescribe con `RL:OK`.

```text
D:\a03\kernel-rd-loader-boot.img  (PRIMER INTENTO, DESCARTADO)
sha256 = b200c8e1aa3ee4235eb1440c0388d44509376f91483fea5403df75a557adae53
```

**Resultado: bootloop.** Control con kernel stock + ramdisk sin `.backup/init.xz`:

```text
D:\a03\kernel-control-nobackup-boot.img
sha256 = 8f32c635d916425dcc3512b92064fdd64684bc91d9442be9b677d6531ecccc69
```

También dio bootloop. Conclusión: **Magisk necesita `.backup/init.xz`**; no se puede quitar.
Además, el ramdisk stock re-comprimido mide 745.463 bytes, a solo 9 bytes del límite de página
(745.472), así que reescribir el CPIO aunque sea con un blob pequeño desborda.

### Ramdisk multi-miembro (estrategia actual)

Dejar el ramdisk stock **byte-idéntico** como primer miembro gzip y añadir un segundo miembro
gzip de 225 bytes con un CPIO que contiene `xnu_payload.bin`:

```text
D:\a03\kernel-rd-loader-boot.img
sha256 = 33f1253949f91fcda31584e6421c411fd3061ca4f7cc60b16b2e5411c5df9444
```

Verificado en build:

```text
stock        : 745033 bytes
2o miembro   : 225 bytes (404 sin comprimir)
total        : 745258 bytes -> pagina 745472 (margen 214)
descomprimido: 827364 bytes
primer miembro byte-idéntico: True
entradas: ... TRAILER!!!, xnu_payload.bin, TRAILER!!!
```

`rd_loader.c` fue modificado para **no parar** en `TRAILER!!!` y seguir escaneando, de modo que
encuentra el segundo CPIO. El resultado esperado es franja verde + franja azul y `RL:OK`.
Si LK solo descomprime el primer miembro gzip, el loader devuelve 0, vuelve a `stext` y Android
arranca con `RL:F` (fallo seguro).

**Resultado:** Android arranca, pero `/proc/version = RL:F` y no hay franja azul. LK solo descomprime
el primer miembro gzip. El DTB de arranque tampoco sirve: `stock/dtb` tiene magic `0xD7B7AB1E`
(DTB gzip de Android) y 0 bytes de padding.

### Blob embebido en el payload del kernel (estrategia actual)

El blob va justo después del loader dentro del payload inyectado al final del kernel. El ramdisk
queda 100% stock. Dos palabras `0xDEADBEEF` se parchean con el offset y la longitud del blob.

```text
D:\a03\kernel-kblob-boot.img
sha256 = 6817ff6f4b171741c9e9f068be51077bc426375b338bc336bff413b46f4dd8c3
payload = 624 bytes @ 0x169e810  (loader 472 + blob 152)
```

Diferencias respecto al `blob_loader.S` descartado anteriormente:

- destino `0xA1000000` en vez de `0x92500000`;
- `dc civac` + `ic ivau` por línea + `ic iallu` + `dsb`/`isb` en vez de solo `ic iallu`;
- argumentos `x0=image_base`, `x1=FDT`, `x2=stext` al blob.

Resultado esperado: franja verde + franja azul, `/proc/version = RL:OK`.

**Resultado: ÉXITO.** Confirmado por el usuario: franja azul visible y `/proc/version = RL:OK`.

Estado del pipeline de arranque:

```text
LK -> code0 parcheado -> payload en 0x169e810
       -> boot_args + FDT + handoff validado (:XNUOK)
       -> loader fase 2: blob embebido -> copia a 0xA1000000
       -> dc civac + ic ivau + ic iallu + isb
       -> salto al blob -> RL:OK + franja azul
       -> retorno a stext -> Android
```

El mecanismo de carga de un blob ejecutable está validado. El siguiente bloqueo es de **espacio**:
solo caben ~925 KB antes del trailer Samsung, y un XNU real ocupa 20-30 MB.

### Kernel sintético (estrategia para liberar espacio)

Sustituir los 23.7 MB de Image de Linux por un Image ARM64 mínimo de 514 KB. El header es
válido (`code0 = b 0x80000`, `text_offset = 0x80000`, `image_size = 0x80800`, `magic = ARMd`,
`flags = 0xa`), con el payload en `0x80000`. El ramdisk y el DTB quedan stock.

```text
D:\a03\kernel-synth-boot.img
sha256 = c6b91f1f0123bfb756aa88e9d3cf4e3f308758cd715a0051f57081d6beaa3871
Image  = 526336 bytes (514 KB)  -> ~23 MB libres antes del trailer
loader = 280 bytes, blob = 104 bytes @ payload+0x118
```

Archivos nuevos:

- `stub/synth_loader_entry.S` — calcula `image_base = PC - 0x80000`, sin stack.
- `stub/rd_loader.c` — añadido `-DSYNTHETIC`: desactiva los marcadores en
  `image_base + 0x10623A0` (caerían fuera del Image y podrían pisar ramdisk/DTB).
- `stub/synth_test_blob.S` — franja magenta en y=200..399 + `wfe`.
- `stub/build_synth_kernel.py` — genera el Image ARM64 mínimo.
- `stub/build_synth_boot.sh` — pipeline completo.

Verificado en build: `objdump` confirma que `code0` es un `B` a `0x80000`, el payload arranca
con `adr x20,_start`, y el loader sintético **no referencia `sp`** (no necesita stack).

Resultado esperado: franja **magenta** ancha y pantalla congelada. No habrá `/proc/version`
(no hay Linux). Si el dispositivo se reinicia en vez de congelarse, sospechar de un watchdog
de LK y cambiar `wfe` por un bucle alimentando el watchdog.

**Resultado: ÉXITO.** Confirmado por el usuario: franja magenta ancha y pantalla congelada.
LK aceptó el Image sintético de 514 KB. Ya no dependemos de Linux para el arranque.

Pipeline validado de extremo a extremo:

```text
LK -> Image ARM64 sintetico (code0 = b 0x80000)
    -> payload@0x80000: loader sin stack
    -> copia blob a 0xA1000000
    -> dc civac + ic ivau + isb
    -> salto al blob -> franja magenta + wfe
```

Estado: ~23 MB libres antes del trailer Samsung. El loader admite hasta 32 MB (`MAX_BLOB`).
Siguiente bloqueo: no existe un XNU/Mach-O compilado para T606; el `12377.121.6` del repo A71
es de referencia (iPhone 11/N104AP, UFS) y **no es drop-in** (eMMC, GIC/UART/clocks distintos).

Tras la prueba, restaurar el boot rooteado stock.

Estado consolidado del bring-up hasta este punto:

| Canal | Verificación | Estado |
|---|---|---|
| Framebuffer 720×1600 @ `0x9E000000` | texto legible en foto `20261122_161703.jpg` | ✅ |
| `boot_args` @ `0x92000000` | checksum `47fafc26260af341` | ✅ |
| FDT detectado | sufijo `D` (magic `0xEDFE0DD0`) | ✅ |
| Handoff estilo `_start` | sufijo `:XNUOK` + franja verde | ✅ |
| Arranque de Android | shell `a03:/ $` responde | ✅ |

Esto completa la **consola de debug** del bring-up. El usuario no tiene UART; el framebuffer la
sustituye. Todavía no hay kernelcache de XNU para T606.

## Handoff estilo `_start` en el kernel sintético

El bloqueo de espacio quedó resuelto: el Image sintético tiene ~23 MB libres antes del trailer.
Ahora faltaba validar que podemos entregarle a XNU **exactamente** lo que espera `_start`: no un FDT
en `x0`, sino `x0 = &boot_args` con el layout de 1152 bytes de `docs/02`.

```text
D:\a03\kernel-handoff-boot.img
sha256 = d85f2d53cf6e616ee249ce73b31837d29a19d16e8bb3456aaf81bfe35296c4d3
Image  = 903168 bytes (882 KB)
loader = 728 B, blob = 312 B, DTB crudo = 376049 B (a03.dtb)
```

**Primer intento (`fe805ae8...`): franja roja.** Causa encontrada por revisión del `objdump` del blob:
la comprobación de `physBase` construía `0x80000000` con `movk ..., lsl #32` (que da
`0x8000000000000000`). Corregido a `lsl #16`. El loader y `boot_args` no tenían la culpa.

Payload = `loader + blob + a03.dtb`. Cuatro palabras `0xDEADBEEF` se parchean con
`blob_off=0x2d8`, `blob_len=0xd8`, `dtb_off=0x3b0`, `dtb_len=376049`.

`xnu_handoff_loader.c` hace, con MMU off y sin stack:

1. copiar el DTB crudo a `0x92001000` + coherencia;
2. copiar el blob a `0xA1000000` + coherencia;
3. construir `boot_args` en `0x92000000`: `Revision=Version=2`, `virtBase=0xfffffff007004000`,
   `physBase=0x80000000`, `memSize=memSizeActual=0xfffff000`, `deviceTreeP=0x92001000`,
   `deviceTreeLength=376049`, `CommandLine="debug=0x8 kext-dev-mode=1"`, `bootFlags=0`;
4. devolver `0xA1000000`; el entry pone `x0=0x92000000` y salta al blob.

Verificado con `objdump`: `strh` en @0/@2, `str` en @8/@16/@24/@96/@104, CommandLine en @108,
`bootFlags` en @1136, `memSizeActual` en @1144. Cero referencias a `sp`.

`xnu_handoff_blob.S` valida los campos y dibuja **7 barras de 16 filas** desde y=200.
Verde = check OK, rojo = check fallido:

| y | Check |
|---|---|
| 200 | `x0 == 0x92000000` |
| 216 | `Revision == 2` |
| 232 | `Version == 2` |
| 248 | FDT magic `0xEDFE0DD0` en `deviceTreeP` |
| 264 | `deviceTreeLength == 376049` |
| 280 | `CommandLine[0] == 'd'` |
| 296 | `physBase == 0x80000000` |

Si no hay barras, el loader no corrió. Si alguna barra es roja, ese campo es el problema.

Esto valida el contrato de entrada de XNU **sin** necesitar un kernelcache. Lo que aún no existe es
el XNU compilado para T606: el `12377.121.6` del repo A71 es de referencia (iPhone 11/N104AP, UFS)
y no es drop-in (eMMC, GIC/UART/clocks distintos). Tampoco hay SEP ni userland de Apple; el objetivo
sigue siendo una consola XNU propia, no iOS.

**Resultado: CONFIRMADO — 7 barras verdes** (franja verde continua de 112 filas en y=200..311).
`boot_args`, FDT y `x0` correctos. Tras la prueba, restaurar el boot rooteado stock.

## Loader Mach-O estilo iBoot

Pasando de "blob arbitrario" a "kernelcache": el loader ahora parsea un Mach-O arm64 incrustado
en el payload, carga sus segmentos y salta a su entry con `x0 = &boot_args`.

```text
D:\a03\kernel-macho-boot.img  (PRIMER INTENTO, DESCARTADO)
sha256 = 3b6686912698b2c3822ba88792e300d3df78791fe9701c3fab6da0ca9b80c7e9
```

**Resultado: se reinició.** Causa: el Mach-O sintético estaba mal formado. `__TEXT` tenía
`vmaddr = link_base` pero `fileoff = 0x4000`, así que el loader copiaba el código a
`KERN_PHYS = 0xA2000000` mientras `LC_UNIXTHREAD` apuntaba a `KERN_PHYS + 0x4000`
(que quedaba a cero) → salto a `udf` → reinicio. El loader estaba bien; el archivo de prueba no.

Mach-O corregido: `__TEXT.fileoff = 0`, `filesize = 0x4060` (todo el archivo). Entonces
`vmaddr + i -> fileoff + i` y el código en `fileoff 0x4000` cae en `0xA2004000`, que es el entry.

```text
D:\a03\kernel-macho-boot.img  (SEGUNDO INTENTO, DESCARTADO)
sha256 = 021c4f0bfcca103ad0786bfb1bb9a9d54b9319c542db909b897e47ee8102b5c3
```

**Resultado: se reinició otra vez.** Segundo bug en el generador: al parchear `filesize` usé
offset 40 del segmento, que es `fileoff` (campo correcto: 48). Resultado: `fileoff=0x4060`,
`filesize=0` → el loader no copiaba nada y el entry volvía a caer en ceros.

Tercera versión, con `fileoff=0`, `filesize=0x4060` y verificación de que el bytes del entry
no son cero (`c8 02 00 58` = `ldr x8, ...`):

```text
D:\a03\kernel-macho-boot.img
sha256 = 49c8d12d4a04fc5b52d0d8080beb091cad6b9ca584ad5528ff9dad3873dcb57b
Image  = 919552 bytes (898 KB)
loader = 1952 B, Mach-O sintetico = 16480 B, DTB = 376049 B
segmento: vmaddr=0xfffffff007004000 vmsize=0x10000 fileoff=0 filesize=0x4060
entry   : pc=0xfffffff007008000 -> fisico 0xA2004000
codigo  : c8020058 (ldr x8, =FB_LOGO)
```

`macho_loader.c`:

- valida `MH_MAGIC_64` (`0xfeedfacf`) y `CPU_TYPE_ARM64`;
- primera pasada: `__TEXT` da el `link_base`, `LC_UNIXTHREAD` da el PC virtual;
- segunda pasada: cada `LC_SEGMENT_64` se copia a
  `KERN_PHYS + (vmaddr - link_base)`, con `KERN_PHYS = 0xA2000000`, y se hace
  `dc civac` + `ic ivau` + `isb` sobre el segmento;
- construye `boot_args` con `virtBase = link_base`, `deviceTreeP = 0x92001000`,
  `deviceTreeLength = 376049` y `topOfKernelData` = fin real de segmentos;
- devuelve el entry físico; `macho_entry.S` pone `x0 = 0x92000000` y salta.

El entry del Mach-O sintético (`macho_test_stub.S`) dibuja una franja **magenta** en
y=320..335. Si aparece, el pipeline completo "LK → Image sintético → Mach-O → entry → framebuffer"
está validado.

**Limitación honesta:** con un XNU real habrá que revisar cómo `start.s` usa `physBase`/`virtBase`
para mapear el kernel: aquí el kernel se carga en `0xA2000000`, no en `0x80000000`. Además,
`macho_entry.S` instala un stack temporal en `0x93000000` porque el parser C usa spill.
Sigue sin existir XNU compilado para T606, ni SEP/userland de Apple.

**Resultado: ÉXITO.** Confirmado por el usuario: apareció la franja magenta en y=320..335.

Pipeline validado de extremo a extremo:

```text
LK -> Image ARM64 sintetico (code0 = b 0x80000)
    -> payload: loader Mach-O + kernelcache + DTB crudo
    -> parsea MH_MAGIC_64 / LC_SEGMENT_64 / LC_UNIXTHREAD
    -> copia segmentos a 0xA2000000 + (vmaddr - link_base)
    -> dc civac + ic ivau + ic iallu + dsb/isb
    -> construye boot_args (1152 B) con deviceTreeP y topOfKernelData
    -> x0 = &boot_args, br al entry del kernelcache
    -> codigo del Mach-O dibuja magenta y se congela
```

Los dos reinicios anteriores fueron bugs del **generador del Mach-O de prueba**, no del loader:
(1) `fileoff=0x4000` con `vmaddr=link_base`; (2) parchear `filesize` en el offset de `fileoff`.
El `verify_macho.py` actual comprueba magic, `ncmds`, `fileoff=0`, `filesize` y que los bytes del
entry no sean cero, para que no se repitan.

Estado consolidado del bring-up:

| Canal / mecanismo | Estado |
|---|---|
| Framebuffer 720×1600 @ `0x9E000000` | ✅ legible, `dc cvac` obligatorio |
| `boot_args` @ `0x92000000` (1152 B, offsets verificados) | ✅ |
| FDT crudo copiado y apuntado por `deviceTreeP` | ✅ |
| Handoff estilo `_start` (`x0 = &boot_args`) | ✅ 7 barras verdes |
| Kernel sintético de 514 KB aceptado por LK | ✅ |
| Loader sin Linux (copia + coherencia + salto) | ✅ |
| Carga de Mach-O con segmentos y entry | ✅ franja magenta |
| XNU real para T606 / drivers IOKit / SEP / userland | ❌ no existe |

Sigue sin existir XNU compilado para T606: el `12377.121.6` del repo A71 es de referencia
(iPhone 11/N104AP, UFS) y no es drop-in. El objetivo alcanzable es una consola XNU propia, no iOS.

No hace falta firmar ni parchear vbmeta. El boot rooteado stock se mantiene como rescate.
