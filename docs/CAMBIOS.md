# Cambios

Lo que trae cada versión. Las notas de las releases de GitHub salen de aquí
(`scripts/publicar-release.sh` lo lee), así que esto es la única copia: una
lista de cambios escrita a mano dentro del script de publicar se queda con la
de la versión anterior el día que alguien tiene prisa.

Una sección por etiqueta, encabezada con `## ` y el nombre de la etiqueta.

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
