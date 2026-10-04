<div align="center">

<img src="build/web/favicon.svg" width="72" alt="">

# MIKE OS

**Un sistema operativo hecho desde cero.**

Kernel Linux propio · init con runit · gestor de paquetes propio · shell propia
· escritorio propio · español e inglés · **cero systemd**

[![Release](https://img.shields.io/github/v/release/macorredor270/mikeos?label=versi%C3%B3n&color=00d4ff)](https://github.com/macorredor270/mikeos/releases/latest)
[![Kernel](https://img.shields.io/badge/Linux-7.2.9-00d4ff)](https://www.kernel.org/)
[![Licencia](https://img.shields.io/badge/licencia-MIT-00d4ff)](LICENSE)
[![Kernel](https://img.shields.io/badge/kernel-7.2-00d4ff)](docs/kernel.md)
[![Plataforma](https://img.shields.io/badge/x86__64-UEFI-00d4ff)](docs/boot.md)
[![Pruebas](https://img.shields.io/badge/pruebas-47%20%2B%2011%20%2B%2013%20%2B%208%20en%20verde-4cc38a)](#comprobar-que-funciona)

[**Web**](https://m1keos.duckdns.org/) ·
[Descargar](https://m1keos.duckdns.org/descargas.html) ·
[Documentación](https://m1keos.duckdns.org/docs/) ·
[Capturas](https://m1keos.duckdns.org/capturas/) ·
[Cambios](docs/CAMBIOS.md) ·
[*Read in English*](https://m1keos.duckdns.org/en/index.html)

</div>

---

> [!NOTE]
> **MIKE OS 0.10.0.** Arranca, se instala junto a Windows, se actualiza y vuelve
> atrás, y todo eso está probado de punta a punta: en QEMU con firmware UEFI
> real —instalando y arrancando lo instalado— y en una Surface Laptop 4 física.
> En otros portátiles lleva sus drivers y su firmware, pero sin probar en el
> equipo concreto. Instálalo primero en uno que puedas formatear.

**Descarga:** [`mikeos.iso`](https://github.com/macorredor270/mikeos/releases/latest/download/mikeos.iso)
(570 MB) · [todas las versiones](https://github.com/macorredor270/mikeos/releases) ·
[qué hay de nuevo](docs/CAMBIOS.md)

### Novedades de la 0.10.0

- **Linux 7.2.9**, la última estable de kernel.org, en vez de un commit de la
  rama de desarrollo.
- **Particionado manual con GParted** en el instalador, como en Calamares, y
  GParted dentro de la ISO: funciona sin internet.
- **Instalar al lado de Windows funciona de verdad**: MIKE OS se registra en la
  UEFI, GRUB va primero con Windows en el menú, y actualizar el kernel ya no
  borra GRUB.
- **Muchos más equipos**: drivers de cada marca de portátil, Intel VMD, gráficas
  Intel y AMD nuevas y viejas, Wi-Fi 7, Ethernet de 2,5 Gb, touchpads, sonido…
  y el firmware que nunca había llegado a la imagen (Wi-Fi Qualcomm, MediaTek,
  NVIDIA, Surface Pro, sonido de Intel).
- **El microcódigo de la CPU se carga** al arrancar. No se había cargado nunca.

| | |
|---|---|
| Arranque | **0,59 s** del kernel a la consola |
| Memoria | **324 MB** con el escritorio en pie |
| Compilar el sistema entero | **25 s** |
| systemd | **0 líneas** |
| Idiomas | **español e inglés**, el sistema entero |
| Imagen | **570 MB** |

![El escritorio de MIKE OS](build/web/capturas/escritorio.png)

## Índice

- [Qué es esto](#qué-es-esto)
- [Probarlo](#probarlo)
- [Lo que todavía no funciona](#lo-que-todavía-no-funciona)
- [Construirlo](#construirlo)
- [Comprobar que funciona](#comprobar-que-funciona)
- [Actualizaciones](#actualizaciones)
- [Estructura](#estructura)
- [Colaborar](#colaborar)
- [Licencia](#licencia)

## Qué es esto

No es una distribución de Linux montada con piezas de otras. El kernel se
compila con una configuración propia, el init es runit con servicios escritos
para este sistema, y el gestor de paquetes, la shell, las herramientas y el
escritorio están escritos desde cero para MIKE OS.

**Arranca por dos caminos a la vez, y es a propósito.** GRUB va en
`EFI/BOOT/BOOTX64.EFI`, que es la ruta que prueba toda firmware sin necesidad
de registrar nada, y da menú: arrancar normal, ver los mensajes, entrar sólo a
consola si el escritorio no levanta. Además el kernel se compila con
`CONFIG_EFI_STUB`, así que él solo ya es un ejecutable UEFI válido y queda
registrado aparte como respaldo. Si GRUB desaparece, el equipo enciende igual.
No encender es el peor fallo que puede tener un sistema operativo.

### Las piezas

| Pieza | Qué es |
|---|---|
| **kernel** | Linux 7.2.9, la estable de kernel.org, con ~390 opciones y 9 parches de Surface propios. Todo va dentro (`=y`): no se montan módulos |
| **runit** | Init y supervisión, PID 1 |
| **mpm** | Gestor de paquetes: SHA256, dependencias, instantáneas de btrfs antes de instalar, y rollback |
| **mkshell** | Shell en C: tuberías, redirecciones, variables |
| **mcore** | 37 herramientas del sistema: `m-install`, `m-doctor`, `m-drivers`, `m-energia`, `m-idioma`, `m-particiones`… |
| **instalador** | Gráfico, en QML. Borrar el disco, instalar al lado, reemplazar una partición o particionado manual con GParted; avisa de lo que va a borrar |
| **bloqueo** | Pantalla de bloqueo con `ext-session-lock-v1`, aviso de Bloq Mayús y salida si la cuenta no tiene contraseña |
| **escritorio** | Hyprland, con barra y Centro de Control escritos para MIKE OS en QML |
| **servidor** | Phoenix + PostgreSQL: índice de versiones y parque de equipos |

## Probarlo

```sh
# https://github.com/macorredor270/mikeos/releases/latest
sha256sum -c mikeos.iso.sha256        # comprueba la descarga
sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Arranca en memoria: puedes mirarlo todo, abrir la terminal y apagar sin que el
disco se entere. Para instalarlo, el botón **Instalar MIKE OS** está en la
ventana de bienvenida.

![El instalador enseñando el disco y lo que va a borrar](build/web/capturas/instalador-disco.png)

El instalador detecta el disco solo (y nunca ofrece el USB del que has
arrancado), enseña qué hay en cada partición y avisa en ámbar de lo que se va a
perder. Si algo impediría que el equipo arrancara después, no deja continuar y
explica por qué.

El paso del disco tiene cuatro opciones, como en Calamares:

| | |
|---|---|
| **Borrar el disco** | Lo más sencillo, y lo que quieres en un disco nuevo |
| **Instalar al lado** | Usa sólo el espacio libre y no toca nada más |
| **Reemplazar una partición** | Sólo se borra la que elijas |
| **Particionado manual** | Haces las particiones con GParted (va en la ISO, no hace falta internet), lo cierras y eliges en cuál va MIKE OS |

**Al lado de Windows**, la partición EFI que haya se conserva con el arranque de
Windows dentro, y MIKE OS se registra en la UEFI como primera opción: arranca
GRUB, y en su menú está Windows.

> [!IMPORTANT]
> **Secure Boot hay que desactivarlo.** Este kernel no lleva la firma de
> Microsoft, así que con Secure Boot activado la firmware se niega a
> ejecutarlo. En una Surface: mantén **subir volumen** mientras enciendes.

### Saber qué hardware tienes y qué le falta

```sh
m-drivers            # cada componente, y en cuál de cuatro estados está
m-hardware           # el informe largo: PCI y USB, driver, firmware y servicio
m-energia estado     # perfil de energía, alimentación y batería
```

`m-drivers` distingue **funciona**, **sin driver**, **le falta firmware** y
**detectado pero parado**. Son cuatro averías distintas con cuatro soluciones
distintas que desde fuera se ven todas igual: "no me va el wifi".

## Lo que todavía no funciona

Esto es parte de la documentación, no una nota al pie.

| | |
|---|---|
| **Secure Boot** | Hay que desactivarlo. El kernel no está firmado por Microsoft y no lo va a estar pronto |
| **Sólo UEFI** | No arranca por BIOS ni con CSM |
| **Privilegios** | `m-sudo` da root a la cuenta sin pedir contraseña. El bloqueo protege de miradas, no de alguien con tiempo y teclado |
| **Hardware real** | Probado en QEMU con UEFI real y en una Surface Laptop 4. En otros portátiles, sin probar |

## Construirlo

Necesitas `gcc`, `make`, `git`, `qemu-system-x86_64`, `xorriso` y `mtools`.

```sh
./scripts/build.sh                       # la primera vez compila el kernel
./scripts/crear-iso.sh                   # USB/ISO arrancable
./scripts/run-qemu.sh --gui --desktop
```

> [!NOTE]
> **La ruta del proyecto no puede llevar espacios.** kbuild se niega en seco
> y el `make install` de BusyBox tampoco lo soporta.

Para poder entrar por SSH a la máquina de pruebas, pasa tu clave pública:

```sh
MIKEOS_SSH_AUTHORIZED_KEYS_FILE=~/.ssh/id_ed25519.pub ./scripts/build.sh
```

Las imágenes que se publican se construyen **sin** esa variable, y que
`authorized_keys` quede vacío se comprueba antes de subir nada: una clave de
desarrollo dentro de una imagen distribuida es acceso root para quien la mire.

## Comprobar que funciona

```sh
./tests/humo.sh                    # 47 comprobaciones sobre una máquina arrancada
./tests/raton-real.sh              # 11 comprobaciones con pulsaciones arrastradas
./tests/estatico.sh                # todo lo que no necesita arrancar nada
./tests/instalar-uefi.sh           # instala con UEFI real y arranca lo instalado
./tests/probar-arranque-uefi.sh    # arranca la ISO con firmware UEFI, sin trampas
./tests/arrancar-como-ventoy.sh    # la ISO como ARCHIVO dentro de una partición
./tests/actualizacion.sh           # editar código -> paquete -> mpm upgrade
./tests/medir-arranque.sh          # cronometra el arranque
./tests/barra-posiciones.sh        # la barra sobrevive a moverla de sitio
```

Cada comprobación corresponde a un fallo que ya ocurrió. Tres que merece la
pena explicar, porque explican también cómo se trabaja aquí:

- **`humo.sh`** no comprueba que el código compile: comprueba que el sistema
  arranque, que haya sonido, que XWayland acepte un cliente y que el Centro de
  Control responda. Antes decidía si el panel se había abierto **comparando dos
  capturas de pantalla** — y como la barra lleva un reloj, dos capturas
  separadas por un segundo SIEMPRE salen distintas: aquellas comprobaciones
  pasaban en verde hiciera lo que hiciera el clic. Ahora se le pregunta a la
  barra por IPC.

- **`raton-real.sh`** pulsa **arrastrando 16 píxeles**, como un dedo en un
  touchpad. Qt cancela un toque que se desplace más de 10, así que había
  botones que funcionaban con un clic guionizado perfecto y no con un dedo. Un
  ratón que no se mueve ni un píxel no encuentra nunca ese fallo.

- **`arrancar-como-ventoy.sh`** monta la ISO como un **archivo dentro de una
  partición exFAT**, que es como la lleva mucha gente en el USB. Con la ISO
  grabada en crudo todo pasaba; en un pendrive con Ventoy el arranque llegaba
  al final y moría sin encontrar el sistema.

- **`traducciones.sh`** compara, archivo por archivo, lo que se **pinta**
  contra lo que está **traducido**, sin arrancar nada. Una traducción rota no
  da ningún error: sale una frase en español en mitad de una ventana en inglés,
  y sólo se nota si alguien que habla ese idioma mira esa pantalla concreta.

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

La versión de cada paquete se deriva del **contenido** de sus archivos, no se
escribe a mano. Con números a mano se podía cambiar medio sistema, publicarlo, y
que todos los equipos siguieran diciendo "todo está actualizado" mientras se
quedaban con el código viejo.

## Estructura

```
build/mcore/       las herramientas del sistema
build/desktop/     escritorio: Hyprland, barra (Quickshell), Centro de Control
build/mpm/         el gestor de paquetes y su resolutor de dependencias
build/mkshell/     la shell
build/etc-tree/    el /etc de la imagen y los servicios de runit
scripts/           construir, publicar, generar la web, actualizar el kernel
servidor/          el backend en Elixir/Phoenix
tests/             las pruebas
docs/              documentación (se publica sola en la web)
.config            las opciones del kernel propias de MIKE OS
```

El kernel es la **última estable de kernel.org** (ahora Linux 7.2.9), fijada por
etiqueta y por commit en `scripts/build.sh`. Lo propio de MIKE OS va en dos
sitios: unas 400 **opciones** en `.config` y nueve **parches** de hardware
Surface en `build/kernel-patches/`. Pasar a una estable nueva es una orden:

```sh
./scripts/actualizar-kernel.sh     # trae la estable de hoy, aplica los parches,
                                   # comprueba choques y opciones, y la fija
```

Se planta si algo no cuadra, porque las tres formas en que esto falla son
silenciosas: una opción que la versión nueva renombró desaparece sin avisar, un
parche que "aplica" puede dejar un valor repetido veinte líneas más abajo, y un
driver compilado sin su firmware no da ningún error hasta que falta el Wi-Fi.
Para eso están `tests/kernel-config.sh`, `scripts/choques-kernel.py` y
`tests/firmware.sh`.

## Colaborar

Lee [CONTRIBUTING.md](CONTRIBUTING.md). Lo que más ayuda es **usarlo** y contar
qué se rompe: una foto de la pantalla y la salida de `m-hardware` valen por diez
descripciones.

Un criterio del proyecto, por si sirve de aviso: **un punto no está hecho hasta
que se ha visto funcionar.** No hasta que compila.
[`docs/plan-centro-de-control.md`](docs/plan-centro-de-control.md) lleva el
registro de qué se verificó y cómo, y está lleno de casos en los que el código
era correcto y el comportamiento no.

## Licencia

[MIT](LICENSE) — traducida al español en [LICENCIA.md](LICENCIA.md).
Haz con esto lo que quieras.

La imagen que se descarga lleva dentro software de otra gente, cada uno con su
licencia: ver [AVISOS.md](AVISOS.md). El kernel es GPL-2.0 y el firmware de los
fabricantes es redistribuible pero no libre, y eso se dice en vez de dejarlo
implícito.
