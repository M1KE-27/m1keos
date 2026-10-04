# Cambios

Lo que trae cada versión. Las notas de las releases de GitHub salen de aquí
(`scripts/publicar-release.sh` lo lee), así que esto es la única copia: una
lista de cambios escrita a mano dentro del script de publicar se queda con la
de la versión anterior el día que alguien tiene prisa.

Una sección por etiqueta, encabezada con `## ` y el nombre de la etiqueta.

## v0.10.0

MIKE OS arranca en muchos más equipos. Casi todo lo de esta versión es
hardware que **no funcionaba sin decir nada**: el kernel compilaba, la imagen
arrancaba en QEMU, y en el portátil concreto simplemente faltaba el Wi-Fi, el
sonido o el disco.

### Kernel: la estable de kernel.org

- **Linux 7.2.9**, la última estable (publicada el 3 de octubre). Antes era un
  commit de la rama de desarrollo tomado en mitad de la ventana de fusión de
  7.3 — doce mil cambios sin probar que nadie había publicado como versión.
  Fijado por etiqueta **y** por commit: si la etiqueta cambia en el servidor,
  el build se para.
- **`scripts/actualizar-kernel.sh`** trae la estable del día, aplica los
  parches, comprueba choques y opciones, y sólo entonces la fija. Antes iba a
  la rama de desarrollo y buscaba los parches en una carpeta que no existe.
- Dos parches de Surface **adaptados a mano**. Aplicados con *fuzz* habrían
  entrado sin queja y dejado tres choques: el bit de `btusb` para la Marvell de
  Surface ya era otro flag en 7.2.9, y la Type Cover quedaba con el mismo bit
  que una peculiaridad de otro teclado y con el mismo número de clase que el
  ASUS ROG Z13 — le habría estropeado el teclado a otro equipo.

### Drivers que faltaban

Aquí todo va compilado dentro del kernel: un driver que falta o que queda como
módulo es un equipo que no funciona.

- **Intel VMD** (el "RST" de muchas BIOS Intel desde la 11.ª generación): sin
  él el instalador no veía ningún disco.
- **Gráficas**: `xe` (Intel Lunar Lake y Arc Battlemage, que `i915` no lleva) y
  `radeon` (AMD anteriores a GCN y las HD 7000/R9 200, que no tenían ningún
  driver).
- **Wi-Fi 7 de Intel** (BE200/BE201), **Ethernet** Intel de 2,5 Gb y Broadcom
  — este último se pedía como `TG3`, que no existe: el símbolo es `TIGON3`.
- **Compartir internet desde el móvil por USB** (Android antiguo e iPhone):
  `m-drivers` lo recomendaba cuando no hay red, y no funcionaba.
- **Touchpads** Elantech y Synaptics con dos dedos, receptores **Logitech**,
  lectores de tarjetas **Realtek**, **sonido** de portátiles AMD modernos y los
  amplificadores de altavoz Cirrus/TI.
- **Drivers de cada marca de portátil**: no había ninguno salvo Surface.
  ThinkPad, IdeaPad, ASUS, HP, Dell, Acer, MSI, Samsung, LG, Huawei, Gigabyte,
  Fujitsu, Sony, Panasonic y Toshiba: teclas de brillo y volumen, modo avión,
  retroiluminación, límite de carga y perfiles de ventilador.
- **Temperatura** (Intel DPTF) y **energía** de los Ryzen portátiles (AMD
  PMF), que se caía en silencio por una dependencia.

### Firmware que nunca llegó a la imagen

- El copiado del firmware **no entraba en subcarpetas**. `ath10k/*` sólo
  encuentra carpetas, y el bucle se las saltaba: el **Wi-Fi Qualcomm/Atheros**,
  de los más comunes en portátiles, no tuvo firmware nunca. Lo mismo el
  **Wi-Fi 7 de MediaTek** (mt7925), el de **NVIDIA** (0 de 519 archivos) y el de
  las Surface Pro (Marvell). El comentario del script decía que sí estaban.
- **`regulatory.db`** no estaba: todo el Wi-Fi, de cualquier marca, iba en el
  dominio regulador "mundial", con menos canales y potencia en 5 GHz.
- **Sonido de los portátiles Intel desde 2019** (SOF): 57 MB que en la ISO
  ocupan 2,8.
- **`tests/firmware.sh`** cruza lo que piden los drivers con lo que lleva la
  imagen. Antes de este cambio encontraba 15 drivers dentro del kernel sin un
  solo archivo de su firmware.

### Microcódigo de la CPU

No se había cargado **nunca**, en ningún equipo. El kernel sólo lo coge del
principio del initramfs, y ahí no estaba; la imagen lo dejaba en
`/lib/firmware`, donde no lo mira nadie, y `m-drivers` recomendaba instalar un
paquete que hacía lo mismo. Ahora va delante del initramfs, para AMD e Intel:
son los arreglos de los fabricantes para fallos de la propia CPU (Zenbleed,
o la degradación de los Intel de 13.ª y 14.ª generación).

### Particionado manual en el instalador, como en Calamares

- **Cuarta opción en el paso del disco: "Particionado manual"**, junto a
  borrar el disco, instalar al lado y reemplazar una partición. Haces las
  particiones con GParted, lo cierras, y eliges en cuál va MIKE OS; se
  reutiliza la partición EFI que haya.
- **GParted va dentro de la ISO** y funciona sin internet. Antes era una
  tarjeta aparte que había que descargar, y sin red salía desactivada —
  justo cuando más se instala. Sale en el idioma del sistema (hace falta un
  locale de verdad: se genera `es_ES.UTF-8` sólo para él, porque en todo el
  sistema cambiaría los decimales a coma y rompería scripts que leen números).
- **Al cerrar GParted el instalador vuelve a leer el disco.** Antes seguía
  enseñando las particiones de antes de tus cambios.
- El texto de arriba ya no dice "se borrará todo lo que haya en el disco" en
  los cuatro modos, también al instalar al lado de Windows.
- Probado de punta a punta con firmware UEFI: particionar a mano, instalar en
  la partición elegida reutilizando la EFI, y arrancar lo instalado.

### Arranque dual con Windows

- **El instalador no podía registrar MIKE OS en la UEFI**: `efivarfs` iba como
  módulo en un kernel que no carga módulos. Al lado de Windows eso significa
  que, después de instalar, **el equipo seguía arrancando Windows**. Además
  usaba `--part 1` fijo y apuntaba al kernel saltándose GRUB (sin menú para
  volver a Windows). Ahora: dos entradas, GRUB primero y el kernel detrás como
  respaldo, en la partición EFI que sea.
- **La primera actualización de kernel borraba GRUB**: el paquete del kernel
  copiaba el kernel encima de `EFI/BOOT/BOOTX64.EFI`, que es donde el
  instalador pone GRUB.
- **El kernel anterior se puede arrancar** desde el menú tras una
  actualización. Se guardaba, pero no había forma de llegar a él.
- Una carpeta de fabricante con un espacio en el nombre se perdía al buscar
  otros sistemas, y si se encontraba, GRUB partía su ruta en dos.

### Seguridad

- `m-sudo` limpia `LD_PRELOAD`, `LD_LIBRARY_PATH` y compañía antes de dar root,
  y fija su propio `PATH`.
- `mpm` rechaza nombres de paquete del catálogo remoto con caracteres que
  podrían romper las comillas de una orden de shell.

### Que no vuelva a pasar

- **`tests/estatico.sh`**: todo lo que se comprueba sin arrancar una máquina, de
  una vez.
- **`tests/kernel-config.sh`**: lo que pide el fragmento acaba de verdad en el
  kernel (el `TG3` que no existía, `AMD_PMF` cayéndose, los módulos que aquí no
  se cargan). Y nada escrito dos veces.
- **`scripts/choques-kernel.py`**, dentro del build: se para si un parche deja
  un valor repetido.
- **`tests/menu-dualboot.sh`**: el instalador encuentra a Windows.
- **`tests/instalar-uefi.sh`**: la primera prueba que **instala**. Arranca el
  USB con firmware UEFI real y un disco vacío, instala sin preguntas, apaga,
  quita el USB y vuelve a encender con la misma NVRAM: comprueba que arranca
  por la entrada "MIKE OS", pasando por GRUB, con el kernel, el idioma y los
  subvolúmenes que tocan. 13 comprobaciones.
- `tests/probar-arranque-uefi.sh` arranca ahora la ISO por defecto. Su modo
  anterior (sólo kernel e initramfs) no podía pasar desde hacía meses y daba
  "nunca llega a contestar" en arranques correctos.
- La imagen EFI de la ISO se dimensiona según lo que mide GRUB: tenía 16 MB
  fijos "porque GRUB ocupa unos 2", y GRUB ya ocupa 17 — la ISO dejó de
  construirse.
- El kernel se llama `7.2.9-mikeos` y no `7.2.9-dirty`.
- El firmware que llega sin comprimir (el sonido de Intel) se comprime al
  copiarlo: el kernel lo abre igual.

## v0.7.0-alpha

MIKE OS habla inglés. No la web: **el sistema**.

Desde la primera versión, el instalador abre preguntando *"Choose your
language"*, ofrece English y Español, y debajo promete que se puede cambiar
luego en el Centro de Control. Las dos cosas eran mentira. La elección se
usaba sólo para los avisos del particionado durante la propia instalación y no
se guardaba en ninguna parte; en el Centro de Control no había dónde
cambiarla. Elegías English, instalabas, arrancabas, y tenías un sistema entero
en español. Un idioma que se pregunta y luego se ignora es peor que no
preguntarlo.

### El idioma, de verdad

- **`m-idioma`**: el único sitio donde vive la respuesta. Lo leen la pantalla
  de bienvenida, la barra, el Centro de Control, la pantalla de bloqueo y el
  informe de hardware. Vive en `/etc/mikeos/idioma` y no en el `$HOME` de
  nadie, por lo mismo que la preferencia de energía: lo escribe quien usa el
  escritorio, pero también lo leen procesos que corren como root.
- **Centro de Control → Sistema → Idioma**, que es exactamente donde el
  instalador llevaba años diciendo que estaría. El cambio se ve al instante y
  en toda la ventana, sin cerrar sesión: todo lo que se pinta pasa por una
  función que depende de esa propiedad, así que moverla vuelve a evaluar cada
  enlace.
- **El instalador lo guarda** (`m-install --idioma`). Lo que se elige en la
  primera pantalla es lo que arranca en el disco.
- La pantalla de bloqueo también. Es otro programa — Quickshell la carga
  aparte —, así que el diccionario está en un *singleton* compartido en vez de
  en la barra. Con él dentro de la barra, la única pantalla que ve alguien que
  todavía no ha entrado se quedaba en español.

### El informe de hardware, en el idioma del sistema

`m-drivers` no se queda en la terminal: sus cadenas se pintan en la bienvenida
y en el apartado Controladores. Ahora las categorías y los detalles se
traducen; los **estados** (`ok`, `sin-driver`, `sin-firmware`, `ausente`) no, a
propósito: son identificadores que otros programas comparan para decidir qué
icono pintar, y traducirlos los rompería a todos sin un solo error visible.

### El menú de arranque

El del USB, en los dos idiomas a la vez: GRUB corre antes de que exista el
sistema donde vive la elección, así que no hay forma de saberlo. El del disco
ya instalado sale en uno solo — ahí la respuesta ya se tiene, y un menú
bilingüe permanente es ruido.

### Que no se degrade

- **`tests/traducciones.sh`** (13 comprobaciones) compara, archivo por
  archivo, lo que se **pinta** contra lo que está **traducido**. Hace falta
  porque una traducción se rompe en silencio: nadie ve un error, simplemente
  una frase sale en español en mitad de una ventana en inglés. Lo que se decide
  dejar igual (nombres propios, teclas) va en la lista con su traducción
  idéntica, para que la prueba distinga *"decidido"* de *"olvidado"*.
- **`scripts/capturas.sh --idioma en`**: las capturas de la web inglesa se
  sacan de un escritorio que habla inglés. Hasta ahora la web inglesa enseñaba
  capturas en español — lo único que delataba que era una traducción y no un
  sitio propio.

### La pantalla de bienvenida salía mal, y nadie lo veía

Tenía **dos** juegos de reglas de Hyprland para flotarla y centrarla, en dos
sitios del mismo archivo, y no funcionaba ninguno: tres líneas usaban
`windowrulev2`, que Hyprland 0.56 eliminó, y las otras escribían `float` sin
valor, que esta versión rechaza. Hyprland descarta una regla inválida y sigue
arrancando, así que salía tileada a pantalla completa —con el contenido en la
mitad de arriba y un vacío enorme debajo— desde hace meses. Es la primera
pantalla del sistema y la foto de portada de la web.

Ahora hay un solo juego de reglas, con la sintaxis que esta versión acepta, y
`tests/humo.sh` le pasa a Hyprland cada `windowrule` del archivo para
comprobar que no rechace ninguna en silencio.

Al arreglar eso apareció el fallo de debajo, que era peor: **en un portátil de
1280x800 la ventana era más alta que la pantalla y el botón de continuar
quedaba fuera**. En el USB en vivo eso es quedarse encallado en la primera
pantalla del sistema, sin nada que pulsar. `gtk_window_set_default_size()` es
un tamaño por *defecto*, no un máximo: GTK nunca encoge una ventana por debajo
del tamaño natural de su contenido. Ahora el cuerpo va dentro de una zona que
se desplaza y el pie con el botón se queda siempre visible.

No se había visto nunca porque la máquina de pruebas corre a 1920x1080, donde
cabe de sobra, y porque la pantalla de "versión de prueba" sólo aparece
arrancando en vivo — justo el camino que no se probaba. `tests/humo.sh`
comprueba ahora que la ventana quepa entera, no sólo que flote.

Y el separador del menú de arranque pasó de `·` a un guión: la fuente que
carga GRUB antes de que exista ningún sistema no tiene ese carácter, así que
salía un cuadro vacío en mitad de cada entrada. Eso sólo se ve mirando la
pantalla.

### Arreglado de paso

- `.gitignore` tenía `*.iso`, que también tapaba `build/grub/grub.cfg.iso`. El
  menú de arranque que ve todo el que enciende MIKE OS llevaba desde el
  principio fuera del repositorio: sin historia, sin copia, y lo habría
  borrado un `git clean`.
- Y `build/web/` tapaba las capturas, que **no** son salida generada: salen de
  una máquina arrancada con `scripts/capturas.sh`. Seis estaban en el
  repositorio de antes de esa regla y el resto —el instalador entero, el menú
  de arranque, la pantalla de bloqueo— existían sólo en un disco.
- `scripts/qmldir.sh` llevaba el nombre del único *singleton* escrito a mano.
  El segundo salía declarado como componente normal, y QML entonces crea una
  copia por cada uso — cada una con su propio estado, que es justo lo que un
  *singleton* existe para impedir. Ahora lo detecta leyendo el archivo.
- El Centro de Control se puede cerrar desde fuera (`quickshell ipc ... call
  ajustes cerrar`). Las capturas lo cerraban con un clic en el hueco de al
  lado, que dejaba de funcionar en cuanto había una ventana debajo.
- **SUPER+W y los dos botones de "Tu equipo" de la bienvenida no hacían
  nada.** Llamaban a `quickshell ipc call ...` sin decir qué configuración, y
  eso busca una llamada `default` en `<XDG_CONFIG_HOME>/quickshell/shell.qml`
  — que no es donde vive la de MIKE OS, y la sesión tampoco exporta esa
  variable. El error se lo quedaba un proceso lanzado en segundo plano: al
  pulsar, no pasaba nada y no se decía por qué. Ahora todas llevan `--path`, y
  `tests/traducciones.sh` rechaza cualquier llamada sin selector.

## v0.6.0-alpha

Casi nada de esta versión son funciones nuevas: es hardware que decía funcionar
y no funcionaba. Cada punto de abajo es una avería real que **no dejaba ni un
mensaje de error**, que es justo por lo que duraron tanto.

### Energía

- **Perfiles de energía** (`m-energia`, y apartado propio en el Centro de
  Control): máximo, equilibrado, ahorro y automático. En un sobremesa,
  automático ya significa máximo — no hay batería que cuidar, y lo que se
  ahorra dejando dormir los buses son unos vatios a cambio de latencia en todo
  lo que se toca.
- En un portátil se elige además **qué hace al cerrar la tapa**: apagar la
  pantalla, suspender, hibernar o nada. Suspender e hibernar sólo se ofrecen si
  el equipo los publica de verdad en `/sys/power/state`, e hibernar exige
  además swap del tamaño de la RAM. La sesión se bloquea siempre al cerrar.
- La elección vive en `/etc/mikeos/energia`, no en el `$HOME` de nadie: la
  escribe quien usa el escritorio y la lee el servicio de runit, que es root.
  Con el archivo en `~/.config` el perfil se perdía en cada arranque.

### Controladores

- **Apartado de controladores** en el Centro de Control y en la pantalla de
  bienvenida. Analiza gráfica, red por cable y por USB, Bluetooth, sonido,
  entrada, cámara, discos, procesador y batería, y dice en cuál de cuatro
  estados está cada cosa: funciona, sin driver, le falta firmware, o detectado
  pero parado. Cuatro averías distintas con cuatro soluciones distintas que
  desde fuera se veían todas igual.

### Bluetooth

- **Arreglado de raíz.** El firmware estaba en la imagen desde el principio. El
  problema es que `btusb` se engancha al adaptador *antes* de pedir el firmware,
  así que desde `/sys` un adaptador muerto era indistinguible de uno sano: tenía
  driver. Ahora se rescata desenganchando y reenganchando el driver una vez
  montado el sistema de archivos real.
- `/etc/bluetooth/main.conf`, que no existía: el adaptador se enciende solo al
  aparecer y lo ya emparejado se reconecta.
- Se quita el bloqueo por software de rfkill al arrancar. Sin udev no lo hacía
  nadie, y un adaptador bloqueado es idéntico a no tener Bluetooth.

### Juegos, Java y todo lo que usa X11

- **XWayland se moría al arrancar** porque `xkbcomp` no estaba en la imagen y no
  podía compilar su mapa de teclado. Pero `DISPLAY` seguía exportado, así que
  cualquier programa de X11 intentaba conectarse a un servidor que no existía y
  fallaba muchísimo después hablando de OpenGL. Minecraft era la víctima
  visible. Van `xkbcomp`, `xauth` y `xrandr`.
- 21 variables de entorno para que Firefox, Qt, GTK, SDL, Java y Electron usen
  Wayland en vez de caer a X11 sin decirlo.

### Actualizaciones

- **El paquete `mcore` metía `m-sudo` sin su bit setuid.** La primera
  `mpm upgrade` de cualquier sistema instalado habría dejado a quien la
  ejecutara sin poder ser root y sin poder desbloquear la pantalla — y
  arreglarlo necesitaba justo el sudo que se acababa de romper.
- Le faltaban además doce utilidades que existían en la imagen y que ninguna
  actualización podía tocar nunca. Las dos listas (imagen y paquete) son ahora
  una sola: `build/mcore/utilidades.lista`.

### Otros

- `scp` hacia una máquina MIKE OS fallaba por falta de `sftp-server`, y el error
  nombraba una ruta sin decir que lo que faltaba era un programa.
- Opciones de kernel para estabilidad y ahorro: ACPI_SLEEP, hibernación,
  PCIEASPM, gobernador térmico, zswap, detectores de bloqueo.
- La web se publica en **español e inglés**, con tema claro y oscuro.

### Comprobado

39 comprobaciones de humo y 11 de ratón real, todas en verde, sobre una máquina
arrancada de verdad.
