# 03 — Bootchain, fastboot y la ruta `boot.img`

## Cadena física del A03

```text
BootROM (eFuse)
   ↓
SPL / U-Boot     inicializa DDR
   ↓
LK               fastboot + arranque Android
   ↓
Linux kernel + boot.img + dtb
```

El usuario eligió **no reemplazar SPL ni LK**, sino arrancar con:

```bash
fastboot boot boot.img
```

## Variables fastboot obtenidas

```text
unlocked: yes
secure: yes
verified: FAILED (Unknown variable)
is-unlocked: FAILED (Unknown variable)
```

Notas:

- `unlocked: yes` → AVB desbloqueado.
- `verified` e `is-unlocked` → variables no implementadas en este LK; ignorar.
- `secure: yes` → señal de alerta. Puede significar que la verificación por eFuse sigue activa. **No asumir** que acepta imágenes sin firma.

### Prueba de aceptación (no destructiva)

`fastboot boot` no flashea, así que no hay riesgo de brick:

1. Extraer/repack el `boot.img` stock y hacer `fastboot boot boot.img`. Debe arrancar.
2. Modificar el ramdisk (aunque sea solo añadir un archivo) y repetir `fastboot boot boot.img`.

| Resultado | Conclusión |
|---|---|
| Arranca el modificado | Ruta `boot.img` válida; seguimos |
| Error de verificación de firma | `secure: yes` bloquea; hay que revisar otra estrategia |
| `fastboot boot` no soportado | Idem |

## Plan dentro de `boot.img`

```text
boot.img propio
  ├─ kernel Linux mínimo (o el de A03)
  └─ initramfs
       ├─ xnu-kernelcache.bin  (compilado por nosotros)
       ├─ a03.dtb              (376049 bytes)
       ├─ boot_args.bin        (1152 bytes)
       └─ stub/trampolín
```

Secuencia:

1. LK carga `boot.img` en RAM.
2. El kernel Linux arranca con el initramfs.
3. Un proceso early del initramfs reserva memoria y copia los tres blobs a direcciones fijas.
4. El trampolín:
   - enmascara interrupts,
   - baja a **EL1** si el kernel estaba en EL2,
   - desactiva MMU,
   - limpia/asegura estado de page tables,
   - pone `x0 = &boot_args`,
   - salta a `_start`.
5. XNU toma el control.

## Reglas del trampolín

- No saltar con MMU activa: `start_first_cpu` crea sus propias tablas.
- No saltar desde EL2 directamente: hacer `eret` a EL1 con `SPSR_EL2`/`ELR_EL2` correctos.
- `deviceTreeP` y `deviceTreeLength` deben apuntar al DTB físico.
- `CommandLine` debe ser una cadena de XNU, no `androidboot.*`.
- Evitar `0xA0000000..0xA00B5E49` (initrd) y `0xFD380000` (framebuffer).

## Por qué no SPL ni LK

| Opción | Problema |
|---|---|
| SPL | Firmado por eFuse probable; error = hard brick |
| LK | `secure: yes` puede rechazar LK modificado |
| boot.img | Temporal, no destructivo, usa el `unlocked: yes` que sí tenemos |

Si la prueba de firma falla, el siguiente paso sería investigar una herramienta de arranque ya firmada que permita cargar código propio; no quemar SPL a ciegas.

## fastbootd ≠ fastboot del bootloader

Si entraste con `adb reboot fastboot`, estás en **fastbootd**: el fastboot de Android en userspace. Ahí **`fastboot boot` no existe**.

Para usar `fastboot boot` hay que entrar al fastboot de LK:

```bash
adb reboot bootloader
# o, si ya estás en fastbootd:
fastboot reboot bootloader
```

Comprobación útil si la variable está implementada:

```bash
fastboot getvar is-userspace
# fastbootd  -> yes
# bootloader -> no o variable ausente
```

Los `getvar` que ya funcionaron (`unlocked: yes`, `secure: yes`) vinieron del fastboot de LK, así que `fastboot boot` sí debería estar disponible desde ese modo.

Si aun así no está, se puede arrancar el payload **como kernel** de `boot.img`; ver `stub/README.md` y `stub/make_kernel_image.ps1`.

## Odin como alternativa de flasheo

Samsung usa Odin para paquetes `tar.md5` en Download Mode. Eso **no contradice** los comandos `fastboot` que ya funcionaron: este LK expone ambos caminos.

- `fastboot boot boot.img` → prueba temporal, recomendada.
- Odin con un `tar.md5` que contenga solo un `boot.img` modificado → arranque persistente, útil si `fastboot boot` está deshabilitado o rechaza la imagen.

En cualquier caso **no tocar SPL ni LK**. Odin solo debe usarse para `boot.img`; si el paquete incluye `lk.img`, `spl` o `bootloader`, no flashearlos.

## Comandos útiles (genéricos)

```bash
# extraer boot.img
magiskboot unpack boot.img        # o unpack_bootimg boot.img

# reconstruir
magiskboot repack boot.img

# arranque temporal
fastboot boot new-boot.img
```

Los parámetros reales de `mkbootimg` (base, pagesize, cmdline, dtb offset) deben tomarse del `boot.img` stock del dispositivo.
