# Cambios

Lo que trae cada versión. Las notas de las releases de GitHub salen de aquí
(`scripts/publicar-release.sh` lo lee), así que esto es la única copia: una
lista de cambios escrita a mano dentro del script de publicar se queda con la
de la versión anterior el día que alguien tiene prisa.

Una sección por etiqueta, encabezada con `## ` y el nombre de la etiqueta.

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
