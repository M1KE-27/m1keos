<div align="center">

# MIKE OS

**Un sistema operativo hecho desde cero.**

Kernel Linux propio · init con runit · gestor de paquetes propio · shell propia
· escritorio propio · **cero systemd**

[Descargar](https://m1keos.duckdns.org/descargas.html) ·
[Documentación](https://m1keos.duckdns.org/docs/) ·
[Wiki](https://m1keos.duckdns.org/wiki/) ·
[Capturas](https://m1keos.duckdns.org/capturas/)

</div>

---

> **En desarrollo.** Arranca en hardware UEFI real, se instala y se actualiza,
> pero no hay versión estable ni promesa de que no se rompa nada entre una y
> otra. Si lo instalas, que sea en un equipo que puedas formatear.

| | |
|---|---|
| Arranque | **0,59 s** hasta el prompt |
| Memoria en reposo | **45-55 MB** |
| systemd | **0 %** |
| Imagen completa | ~172 MB |

## Qué es esto

No es una distribución de Linux montada con piezas de otras. El kernel se
compila con una configuración propia, el init es runit con servicios escritos
para este sistema, y el gestor de paquetes, la shell, las herramientas y el
escritorio están escritos desde cero para MIKE OS.

**No lleva gestor de arranque.** El kernel se compila con `CONFIG_EFI_STUB`, así
que es él mismo un ejecutable UEFI: se copia en la partición EFI como
`EFI/BOOT/BOOTX64.EFI` y la firmware lo arranca directamente. Un GRUB menos que
mantener y un sitio menos donde el arranque se puede romper.

### Las piezas

| Pieza | Qué es |
|---|---|
| **kernel** | Linux compilado para este sistema. Todo va dentro (`=y`): no se montan módulos |
| **runit** | Init y supervisión, PID 1 |
| **mpm** | Gestor de paquetes: SHA256, dependencias, instantáneas de btrfs antes de instalar, y rollback |
| **mkshell** | Shell en C: tuberías, redirecciones, variables |
| **mcore** | Las herramientas del sistema: `m-install`, `m-doctor`, `m-volume`, `m-fondo`, `m-internet`… |
| **escritorio** | Hyprland, con barra y Centro de Control escritos para MIKE OS en QML |
| **servidor** | Phoenix + PostgreSQL: índice de versiones y parque de equipos |

## Probarlo

```sh
# descarga desde https://m1keos.duckdns.org/descargas.html
sha256sum mikeos.iso                  # compara con el publicado
sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Arranca en memoria: puedes mirarlo todo, abrir la terminal y apagar sin que el
disco se entere. Para instalarlo, `SUPER/ALT + Return` y `m-install`.

> **Secure Boot hay que desactivarlo.** Este kernel no lleva la firma de
> Microsoft, así que con Secure Boot activado la firmware se niega a
> ejecutarlo. En una Surface: mantén **subir volumen** mientras enciendes.

## Construirlo

Necesitas `gcc`, `make`, `git`, `qemu-system-x86_64`, `xorriso` y `mtools`.

```sh
./scripts/build.sh                       # la primera vez compila el kernel
./scripts/crear-iso.sh                   # USB/ISO arrancable
./scripts/run-qemu.sh --gui --desktop
```

> **La ruta del proyecto no puede llevar espacios.** kbuild se niega en seco
> y el `make install` de BusyBox tampoco lo soporta.

## Comprobar que funciona

```sh
./tests/humo.sh                    # 21 comprobaciones, con clics reales por QMP
./tests/probar-arranque-uefi.sh    # arranca con firmware UEFI, sin trampas
./tests/actualizacion.sh           # editar código -> paquete -> mpm upgrade
./tests/medir-arranque.sh          # cronometra el arranque
```

`humo.sh` no comprueba que el código compile: comprueba que el sistema arranque,
que haya sonido, que la barra siga viva y que el Centro de Control responda a un
clic **de verdad**, inyectado por QMP. Cada comprobación corresponde a un fallo
que ya ocurrió alguna vez.

`probar-arranque-uefi.sh` es el que importa para el arranque: las demás pruebas
usan QEMU pasándole el kernel en la mano, lo que no demuestra nada sobre un
portátil. Esta usa firmware UEFI real y un disco con tabla GPT.

## Actualizaciones

Se piden, no se empujan.

```sh
mpm update && mpm upgrade
```

Todo viaja en paquetes, **el kernel incluido**. Al instalarse, el kernel
anterior se conserva en la partición EFI: si el nuevo no arranca, se elige el
viejo desde el menú de la UEFI y el equipo vuelve.

Con la raíz en btrfs, `mpm` toma una instantánea del sistema antes de tocar
nada y `mpm rollback` vuelve a ella.

## Estructura

```
build/mcore/       las herramientas del sistema
build/desktop/     escritorio: Hyprland, barra (Quickshell), Centro de Control
build/mpm/         el gestor de paquetes y su resolutor de dependencias
build/mkshell/     la shell
scripts/           construir, publicar, generar la web, actualizar el kernel
servidor/          el backend en Elixir/Phoenix
tests/             las pruebas
docs/              documentación (se publica sola en la web)
.config            las opciones del kernel propias de MIKE OS
```

Las modificaciones del kernel son **opciones de `.config`, no parches**. Por eso
`scripts/actualizar-kernel.sh` puede traer una versión nueva de kernel.org y
reaplicarlas, comprobando una a una cuáles siguen existiendo: entre versiones
las opciones se renombran, y una que desaparece en silencio no se nota hasta que
falta el WiFi.

## Colaborar

Lee [CONTRIBUTING.md](CONTRIBUTING.md). Lo que más ayuda es **usarlo** y contar
qué se rompe.

Un criterio del proyecto, por si sirve de aviso: **un punto no está hecho hasta
que se ha visto funcionar.** No hasta que compila. `docs/plan-centro-de-control.md`
lleva el registro de qué se verificó y cómo, y está lleno de casos en los que el
código era correcto y el comportamiento no.

## Licencia

[MIT](LICENSE). Haz con esto lo que quieras.

La imagen que se descarga lleva dentro software de otra gente, cada uno con su
licencia: ver [AVISOS.md](AVISOS.md). El kernel es GPL-2.0 y el firmware de los
fabricantes es redistribuible pero no libre, y eso se dice en vez de dejarlo
implícito.
