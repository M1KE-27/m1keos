# MIKE OS

Un sistema operativo hecho desde cero: kernel Linux propio, init con runit,
gestor de paquetes propio, shell propia y escritorio propio. Cero systemd.

**https://m1keos.duckdns.org** · arranca en 0,59 s y ocupa unos 50 MB de RAM en
reposo.

> En desarrollo. Arranca en hardware UEFI real y se instala, pero no hay
> versión estable ni promesa de que no se rompa nada entre una y otra.

---

## Qué lleva dentro

| Pieza | Qué es |
|---|---|
| **kernel** | Linux compilado para este sistema, con `CONFIG_EFI_STUB`: es su propio ejecutable UEFI y no hace falta gestor de arranque |
| **runit** | Init y supervisión de servicios, PID 1 |
| **mpm** | Gestor de paquetes: verificación SHA256, dependencias, instantáneas de btrfs antes de instalar |
| **mkshell** | Shell en C con tuberías, redirecciones y variables |
| **mcore** | Las herramientas del sistema (`m-install`, `m-doctor`, `m-volume`, `m-fondo`…) |
| **escritorio** | Hyprland, con barra y Centro de Control escritos para MIKE OS |
| **servidor** | Phoenix + PostgreSQL: índice de versiones y parque de equipos |

## Probarlo

Descarga la imagen de <https://m1keos.duckdns.org/descargas.html> y grábala:

```sh
sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Arranca en memoria, así que puedes mirarlo todo sin tocar el disco. Para
instalarlo, abre una terminal con `SUPER/ALT + Return` y escribe `m-install`.

> **Secure Boot hay que desactivarlo.** Este kernel no lleva la firma de
> Microsoft, así que la firmware se niega a ejecutarlo. En una Surface: mantén
> subir volumen mientras enciendes.

## Construirlo

Hace falta un Linux con `gcc`, `make`, `git`, `qemu-system-x86_64`, `xorriso` y
`mtools`. La primera vez se descarga y compila el kernel, así que tarda.

```sh
./scripts/build.sh          # imagen completa
./scripts/crear-iso.sh      # USB/ISO arrancable
./scripts/run-qemu.sh --gui --desktop
```

> El directorio del proyecto **no puede llevar espacios en la ruta**: kbuild se
> niega a compilar desde ahí, y el `make install` de BusyBox tampoco.

## Comprobar que funciona

```sh
./tests/humo.sh                    # 21 comprobaciones, con clics reales por QMP
./tests/probar-arranque-uefi.sh    # arranca con firmware UEFI, sin trampas
./tests/actualizacion.sh           # editar código -> paquete -> mpm upgrade
```

`humo.sh` no comprueba que el código compile: comprueba que el sistema
arranque, que haya sonido, que la barra esté viva y que el Centro de Control
responda a un clic de verdad. Cada comprobación corresponde a un fallo que ya
ocurrió alguna vez.

## Actualizaciones

Se piden, no se empujan.

```sh
mpm update && mpm upgrade
```

El kernel viaja por ahí también, y al instalarse conserva el anterior en la
partición EFI para poder volver si no arranca.

## Estructura

```
build/mcore/       las herramientas del sistema
build/desktop/     escritorio: Hyprland, barra (Quickshell), Centro de Control
build/mpm/         el gestor de paquetes y su resolutor de dependencias
build/mkshell/     la shell
scripts/           construir, publicar, generar la web, actualizar el kernel
servidor/          el backend en Elixir/Phoenix
tests/             pruebas
docs/              documentación (se publica sola en la web)
.config            las opciones del kernel propias de MIKE OS
```

Las modificaciones del kernel son **opciones de `.config`, no parches**: por eso
`scripts/actualizar-kernel.sh` puede traer una versión nueva de upstream y
reaplicarlas, avisando de las que upstream haya renombrado o retirado.

## Licencia

Por decidir.
