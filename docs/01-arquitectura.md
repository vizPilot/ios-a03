# 01 — Arquitectura y límites reales

## Mapeo de versiones

| iOS | Darwin | XNU |
|---|---|---|
| 17.0 | 23.0.0 | `xnu-10002.1.13` |
| 17.1 | 23.1.0 | `xnu-10002.41.9` |
| 17.2 | 23.2.0 | `xnu-10002.61.3` |
| 17.3 | 23.3.0 | `xnu-10002.81.5` |
| 17.4 | 23.4.0 | `xnu-10063.101.15` |
| 17.5 | 23.5.0 | `xnu-10063.121.3` |
| 17.6 / 17.7 | 23.6.0 | `xnu-10063.141.1` |

Objetivo: iOS 17.7, build `21H16`, dispositivo de referencia `iPhone12,1` (`N104AP`, SoC `t8030`).

## Por qué no funciona el kernelcache del iPhone 11

- Está firmado y cifrado dentro de un IMG4/iBoot para `t8030`.
- No puede extraerse de un IPSW y ejecutarse en `T606`.
- Aunque se pudiera descifrar, sus drivers IOKit son para hardware Apple (AIC, AppleUART, AppleT8030…), no para Unisoc.

Por tanto: **compilar XNU desde fuente** es la única vía técnica.

## Bloqueos duros que no resuelve el bootloader desbloqueado

1. **Cadena de arranque de Apple**: iBoot/IMG4/SEP no existen en el A03. Alguien debe hacer ese papel con código propio.
2. **SEP inexistente**: iOS 17 depende del Secure Enclave para keybags, DRM y almacenamiento seguro. El T606 no lo tiene.
3. **Userland cerrado**: `dyld`, `UIKit`, `SpringBoard`, `backboardd` no son reutilizables.
4. **Licencia**: el APSL de XNU prohíbe usar el código para crear/redistribuir copias ilegales de un sistema Apple. Este repo es research-only.

## Lo que sí aporta el A03

- Bootloader desbloqueado → permite `fastboot boot boot.img` propio (pendiente de confirmar por `secure: yes`).
- DTB válido con inventario completo: RAM, CPUs, GICv3, timer, UART, PSCI, clocks, reserved-memory.
- UART física en `0x200b0000` a 115200 8N1 → debug temprano posible.

## Diferencia clave entre FDT de Linux y FDT que espera XNU

El **formato binario** FDT es estándar; lo que no es estándar es el **vocabulario** y los **drivers**:

```text
Linux:  compatible = "sprd,ums9230-uart"  → sprd serial driver
XNU:    necesita un nub/driver IOKit que entienda ese compatible,
        o un compatible propio que registremos en nuestro driver
```

Lo mismo pasa con:

- `arm,gic-v3` frente al controlador de interrupciones de Apple.
- `arm,armv8-timer` frente a los drivers de timer de XNU.
- `arm,psci-0.2` para CPUs secundarias.

El DTB es una **fuente de datos**; no basta con pasarlo a `boot_args.deviceTreeP` y esperar que XNU "arranque solo".

## Comparación rápida

| | iPhone 11 | Galaxy A03 |
|---|---|---|
| SoC | `t8030` | `UMS9230` / T606 |
| CPUs | 2× Lightning + 4× Thunder | 2× A75 + 6× A55 |
| Boot | iBoot → IMG4 → kernelcache | SPL → LK → boot.img |
| Secure | Secure Enclave | No |
| FDT | Apple-style | Linux/Spreadtrum-style |
| Kernel fuente | XNU `10063.141.1` | Linux `4.14.199` (referencia) |
