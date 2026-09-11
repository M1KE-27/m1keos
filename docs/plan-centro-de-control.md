# Centro de Control de MIKE OS — plan de construcción

Panel de ajustes propio y barra modular configurable. La referencia visual es
illogical-impulse, pero **el nombre, el vocabulario y la organización son
nuestros**: aquí no se copia texto ajeno, se construye lo equivalente con la voz
de MIKE OS.

---

## Cómo se trabaja

Un punto a la vez, en orden. Ninguno se marca sin haber pasado por los cinco
pasos:

1. **Desarrollar** — escribir el código.
2. **Construir y arrancar** — `./scripts/build.sh` o, si vale, `./scripts/dev.sh`.
3. **Capturar** — captura de pantalla del resultado real, no del código.
4. **Analizar** — mirar la captura y comprobar el criterio de verificación.
5. **Decidir**:
   - **SÍ** (funciona y se ve bien) → marcar `[x]`, anotar la fecha, siguiente punto.
   - **NO** (falla, o el diseño no convence) → **no se marca**, se anota qué falla
     en *Incidencias* y se sigue en ese mismo punto hasta que pase.

### Reglas que no se saltan

- **Sin puntos huérfanos.** Un ajuste sólo entra cuando existe la función que
  controla. Nada de interruptores que no hacen nada.
- **Interconectado.** Todo ajuste se lee y se escribe en un único sitio
  (`~/.config/mike/settings.conf`, sintaxis Lua) y se aplica por un único camino
  (`m-apply-settings`). Nada de rutas paralelas.
- **Sin regresiones.** Antes de marcar un punto, la barra sigue viva, el
  escritorio arranca y el punto anterior sigue funcionando.
- **Voz propia.** Nombres, iconos y textos de MIKE OS. La referencia sirve para
  la estructura y la calidad, no para el copia y pega.

### Nuestro vocabulario

| Referencia | En MIKE OS | Por qué |
|---|---|---|
| Archivo de configuración | **Editar a mano** | Dice lo que hace, no dónde está |
| Rápido | **Vistazo** | Es la pantalla de entrada |
| General | **Sistema** | Ahí va lo del equipo, no lo del aspecto |
| Fondo | **Escritorio** | Incluye fondo y widgets, no sólo el fondo |
| Abrazo / Flotante / Rectángulo | **Pegada / Isla / Completa** | Describe la forma real |
| Píldoras / Separado por líneas | **Islas / Continua** | Coherente con "Isla" |
| Estilo de esquina | **Bordes de pantalla** | Se entiende sin pensar |
| Widget | **Panel** | Ya usamos "panel" en todo el sistema |

---

## Bloque 0 — Cimientos

Sin esto, lo demás no se puede interconectar. Va primero, entero.

- [x] **0.1 Esquema de ajustes ampliado** — *31 ago 2026*
  `~/.config/mike/settings.conf` pasa de 7 claves a 14 organizadas en tres
  secciones (Barra, Escritorio, Sistema), con comentarios alineados que
  documentan los valores válidos de cada una.
  *Verificado:* borrado el archivo en la VM, se regenera completo con las 14
  claves y la barra sigue viva.

- [x] **0.2 Lector y escritor únicos** — *31 ago 2026*
  `m-apply-settings` es el único que lee y escribe. Nueva función `leer` con
  validación por tipo (`bool`, `color`, `entero:min:max`, `opcion:a:b:c`,
  `lista`, `texto`): un valor inválido se descarta y se usa el de fábrica.
  *Verificado:* con las seis claves corruptas a la vez (`bar_position =
  "diagonal"`, `workspace_count = 47`, `accent_color = "rm -rf /"`,
  `kb_layout = "; whoami"`…) el escritorio arranca igual, se generan 4
  espacios, el teclado queda en `us,es` y el acento en `#00d4ff`.

- [x] **0.3 Registro de módulos de la barra** — *31 ago 2026*
  Catálogo de componentes en `shell.qml.template` y tres listas ordenadas
  (`bar_left`, `bar_center`, `bar_right`) que deciden qué se pinta y dónde.
  La barra ya no tiene módulos escritos a mano: recorre las listas y envuelve
  cada uno en una isla común, así que agrupar y reordenar después es cambiar
  datos, no código. Catálogo inicial: `identidad`, `espacios`, `reloj`,
  `ajustes`.
  *Verificado:* movido el reloj a la izquierda e identidad a la derecha desde
  el archivo, el cambio se ve tras aplicar; un nombre inexistente en la lista
  no pinta nada y no tumba la barra.
  *De paso:* fuera el punto verde de red, que era decorativo. El estado de red
  vuelve como módulo con datos reales en el punto 1.12.

- [x] **0.4 Ventana del Centro de Control** — *31 ago 2026*
  Ventana centrada sobre fondo oscurecido, con navegación lateral de ocho
  apartados y el botón de edición manual encima. Sustituye al desplegable
  colgado de la barra, que se quedaba corto de ancho. Los controles que ya
  funcionaban se reparten por apartados en vez de perderse: sonido, red,
  Bluetooth y fondo en *Vistazo*; teclado en *Sistema*; posición en *Barra*;
  espacios, desenfoque, opacidad, animaciones y acento en *Escritorio*.
  Los apartados sin función todavía lo dicen con una nota, en lugar de
  enseñar interruptores que no harían nada.
  *Verificado:* captura con los ocho apartados navegables y *Acerca de*
  mostrando la ficha de MIKE OS con sus datos reales.
  *Incidencia corregida sobre la marcha:* la primera versión dejaba que la
  columna de navegación creciera hasta comerse la ventana; se fija el ancho
  por los tres lados (`minimum`, `preferred`, `maximum`).

- [x] **0.5 Botón "Editar a mano"** — *31 ago 2026*
  Abre `settings.conf` en el editor dentro de una terminal.
  *Verificado:* el archivo aparece abierto en vi con su contenido.
  *De paso:* `m-terminal` no sabía ejecutar un comando —siempre abría una
  shell de login—, así que se le añade `-e` / `--exec`. Era una carencia
  propia del terminal, no sólo de este botón.

---

## Bloque 1 — Barra

Lo que se usa todos los días. Es la prioridad después de los cimientos.

### 1A · Forma

- [x] **1.1 Posición: Arriba / Abajo / Izquierda / Derecha** — *31 ago 2026*
  La barra gira de verdad: en los laterales los módulos se apilan en columna,
  la identidad se reduce al rombo (no cabe "MIKE OS" escrito), el reloj parte
  la hora sobre los minutos y el espacio activo se estira en vertical.
  *Verificado:* captura en las cuatro posiciones con los módulos legibles.
  *Incidencias corregidas antes de marcar:* `settingsState` se había perdido
  al reestructurar el panel en 0.4; anclajes al padre dentro de posicionadores
  dejaban módulos sin pintar; `implicitHeight: 0` colapsaba la ventana a 48 px
  y sólo cabía el primer módulo; y el motor de layouts no recolocaba las zonas
  al cambiar de orientación, así que se sustituye por tres zonas ancladas a
  los extremos y al centro.

- [x] **1.2 Forma: Pegada / Isla / Completa** — *31 ago 2026*
  *Isla:* franja transparente, cada módulo una cápsula suelta con su borde.
  *Pegada:* fondo continuo que se desborda por el lado que toca la pantalla,
  de modo que sólo se ve redondeado por dentro. *Completa:* franja sólida y
  recta, sin redondeos ni fondo por módulo.
  *Verificado:* captura de las tres, claramente distintas.
  *Bug de fondo encontrado aquí:* `lua_get` exigía que la línea terminara
  justo tras el valor, así que con el comentario que documenta las opciones a
  la derecha **no casaba nunca** y todas las claves caían al valor de fábrica.
  No se había detectado porque las pruebas anteriores usaban archivos sin
  comentarios y porque los valores leídos coincidían con los de fábrica. Ahora
  se verifica siempre con valores distintos a los de fábrica.
  *También:* el Centro de Control reescribía `settings.conf` entero con las
  siete claves que conocía, borrando forma de barra, listas de módulos y
  reloj. Se añade `m-apply-settings set clave=valor`, que actualiza en su
  sitio y conserva el resto, comentarios incluidos.

- [x] **1.3 Agrupación: Islas / Continua** — *31 ago 2026*
  Nueva pieza `Zona`, que envuelve los módulos de un extremo o del centro.
  Con *islas* cada módulo lleva su cápsula y su aire; con *continua* los de
  una misma zona comparten una sola cápsula y se separan con una línea fina,
  que no se dibuja tras el último. Sólo aplica cuando la barra es
  transparente: con la barra ya pintada nadie repite fondo.
  Las seis declaraciones de zona (tres posiciones por dos orientaciones) se
  reducen a tres, porque `Zona` ya resuelve la orientación.
  *Verificado:* captura de ambas, con reloj y ajustes juntos y separados.

- [x] **1.4 Bordes de pantalla: Rectos / Redondeados** — *31 ago 2026*
  Cuatro ventanas de capa de 14×14, una por esquina, por encima de todo y con
  máscara de entrada vacía para no robar clics. Cada una pinta un cuadrado
  negro menos un círculo, con lo que queda el trozo entre el pico y el arco.
  *Verificado midiendo píxeles, no a ojo:* apagadas hay 1 capa y las cuatro
  esquinas son fondo; encendidas hay 5 capas y las cuatro dan negro puro, con
  el fondo intacto más allá del radio. A ojo no se distinguía porque el
  wallpaper es casi negro en las esquinas.
  *Camino recorrido:* con una sola ventana a pantalla completa y cuatro
  lienzos dentro, los recortes inferiores no se colocaban ni con anclajes ni
  con posición explícita; además la barra empujaba la ventana 48 px hacia
  abajo hasta ignorar la zona exclusiva, y `Canvas` sólo pintaba el primero de
  los cuatro si no se le pedía repintar.
  *Pendiente, no entregado:* la tercera opción de la referencia, "salvo
  pantalla completa", necesita detectar ventanas a pantalla completa. El
  módulo de Hyprland de Quickshell no expone esa información en esta versión
  (su archivo de tipos viene vacío), así que se deja fuera en lugar de añadir
  un botón que no haría nada.

- [x] **1.5 Tamaños** — *31 ago 2026*
  Alto de barra (24-96), alto de módulo (18-72), tamaño de letra (8-24) y
  separación (0-24), con un control numérico reutilizable (`Numero`).
  Los tres tamaños se limitan **entre sí**, no sólo por su rango propio: un
  módulo más alto que la barra o una letra más alta que el módulo se recortan
  a lo que cabe. El margen de la barra pasa a ser proporcional a su alto.
  *Verificado en ambos extremos.*
  *Incidencia corregida antes de marcar:* los puntos de espacio de trabajo
  tenían medidas fijas, así que al subir la letra a 24 px el número del
  espacio activo se salía del punto y salía recortado por arriba y por abajo.
  Ahora se derivan del tamaño de letra.
  *También:* `dev.sh qml` sólo copiaba dos componentes, así que al añadir uno
  nuevo el panel fallaba con "no es un tipo". Ahora copia todos.

- [x] **1.6 Ocultar automáticamente** — *31 ago 2026*
  Con autoocultar la barra se retira y deja una tira sensible de 3 px pegada
  al borde; al acercar el cursor vuelve, y se esconde de nuevo al alejarse.
  Mientras esté encima o el Centro de Control abierto, no se va. Además deja
  de reservar espacio, o quedaría un hueco vacío donde estaba.
  *Verificado moviendo el cursor de verdad* (eventos absolutos por QMP, que
  sí funcionan donde no funcionaba el monitor de QEMU): oculta 1920×3 →
  cursor al borde → 1920×48 → cursor lejos → 1920×3.
  *Incidencia corregida antes de marcar:* la cuenta atrás sólo arrancaba al
  salir el cursor de la barra, así que si uno se asomaba al borde y se iba sin
  llegar a tocarla, la barra se quedaba visible para siempre. Ahora también
  arranca al aparecer.

- [x] **1.7 Transparencia de la barra** — *31 ago 2026*
  Opacidad de 20 a 100. Se aplica al color del fondo, no al elemento entero:
  bajando la opacidad del módulo se irían con él el texto y los iconos, y la
  barra quedaría ilegible en vez de translúcida.
  *Verificado midiendo el mismo píxel de fondo:* 100 % da el color pleno del
  módulo, 50 % lo mezcla con el fondo de pantalla y 20 % queda casi el
  fondo.

### 1B · Módulos

Cada uno: dato real, sin inventar. Se marca cuando muestra información
verdadera y responde al clic.

- [x] **1.8 Identidad** — *31 ago 2026* · logo y nombre; al pulsarlo abre el
      Centro de Control directamente en *Acerca de*. *Verificado con un clic
      real:* se abre la ficha del sistema.
- [x] **1.9 Espacios de trabajo** — *31 ago 2026* · puntos con el activo
      marcado. *Verificado con un clic real* sobre el segundo punto: el
      escritorio pasa del espacio 1 al 2.
- [x] **1.10 Reloj** — *31 ago 2026* · formato y segundos desde *Sistema*.
      *Verificado los cuatro modos:* `04:05`, `04:05 am`, `04:05 AM` y
      `04:05:35`. Sin segundos despierta al cambiar de minuto; con segundos,
      cada segundo.
- [x] **1.11 Volumen** — *11 sep 2026* · nivel real, rueda para subir y
      bajar, clic silencia. Sin destino de audio sigue diciendo "sin audio"
      en vez de inventarse un número.
      *Verificado con ratón de verdad (eventos por QMP):* la barra marca
      95 %, tres golpes de rueda hacia abajo la dejan en 80 % y el clic
      alterna el silencio.
      *La incidencia que lo bloqueaba no era libudev-zero.* El kernel traía
      el controlador HDA pero **ningún driver de códec**
      (`CONFIG_SND_HDA_GENERIC` y los demás estaban desactivados), así que
      moría en `Cannot probe codecs, giving up` y arrancaba con cero
      tarjetas. Estaba en `dmesg` desde el principio. Añadidos al fragmento
      `.config` del proyecto el códec genérico —el que expone QEMU— más
      Realtek, HDMI, Analog, Conexant y USB Audio para hardware real.
      *Fallo corregido de paso:* estando silenciado, `m-volume get` imprimía
      sólo `mute` y se perdía el nivel, así que la barra no distinguía
      "silenciado" de "no hay tarjeta" y ponía **"sin audio" en un sistema
      con sonido perfectamente montado**. Ahora devuelve siempre el número,
      con " mute" detrás si procede.
- [x] **1.12 Red** — *31 ago 2026* · muestra la conexión real: nombre de la
      red WiFi si la hay, o la interfaz de cable, o "sin red". Al pulsarlo
      abre el apartado de red del Centro de Control.
      *Verificado:* el módulo enseña `⇄ eth0`, dato leído del sistema, y el
      clic abre el panel, que ahora dice "Conectado por cable · eth0".
      *Dos fallos corregidos de paso:* `m-network` no encontraba `ip` ni
      `ifconfig` porque viven en `/sbin` y no estaban en el PATH, así que
      `m-network status` salía vacío; y el apartado de red del panel sólo
      hablaba de WiFi, de modo que con cable conectado parecía que no había
      red.
- [ ] **1.13 Bluetooth** — estado real; clic abre el panel de Bluetooth.
- [ ] **1.14 Reproducción** — qué suena y controles; oculto si no hay nada.
- [x] **1.15 Medidores** — *31 ago 2026* · CPU y memoria de `/proc`, con
      barrita además del número y refresco configurable (`metrics_interval`).
      La barra se pone ámbar al pasar del 75 %, para que un pico se note sin
      leer la cifra.
      *Verificado con carga real:* en reposo marca CPU 0 % y RAM 7 %; con seis
      bucles ocupando la máquina sube a 92 % y la barra cambia a ámbar.
      La CPU se calcula comparando con la lectura anterior guardada, no
      durmiendo dentro del script: así cada consulta es inmediata. La memoria
      usa `MemAvailable`, no `MemFree`, que dejaría fuera la caché reclamable
      y haría parecer el sistema mucho más lleno de lo que está.
- [ ] **1.16 Bandeja** — iconos de aplicaciones, anclar y colorear.
- [x] **1.17 Botones rápidos** — *31 ago 2026* · lista configurable
      (`bar_buttons`) con los que tienen función real detrás: **captura de
      pantalla** y **cambio de teclado**, que además enseña la distribución
      activa.
      *Verificado con clics reales:* la captura creó un PNG de 629 KB en
      `~/Pictures/Screenshots`, y el botón de teclado pasó de US a ES,
      aplicándolo a Hyprland y actualizando su propia etiqueta.
      *De paso:* `m-screenshot full` captura la pantalla entera sin pedir
      región, que es lo que tiene sentido desde un botón.
      *No entregados, por no tener función detrás:* micrófono y claro/oscuro
      dependen de audio y de un tema claro (bloques 2 y 3); grabar y selector
      de color necesitan `wf-recorder` y `hyprpicker`, que no están en la
      imagen; y el perfil de rendimiento necesita `cpufreq`, que no existe en
      la máquina virtual y no se puede verificar aquí.
- [ ] **1.18 Avisos** — contador de no leídos (depende del Bloque 4).

### 1C · Composición

- [x] **1.19 Añadir módulo** — *31 ago 2026* · catálogo de los ocho módulos
      existentes, cada uno con botón para colocarlo en izquierda, centro o
      derecha. Colocarlo en una zona lo retira de las demás, o saldría
      repetido en la barra.
- [x] **1.20 Quitar módulo** — *31 ago 2026* · ✕ en cada módulo colocado.
- [x] **1.21 Reordenar** — *31 ago 2026* · ‹ y › mueven dentro de la zona; el
      salto entre zonas se hace colocándolo de nuevo, que es más claro que un
      arrastre que salta de sitio.
- [x] **1.22 Unir y separar** — *31 ago 2026* · con agrupación continua los
      módulos de una zona comparten cápsula (ver 1.3).
  *Verificado:* barra montada distinta de la de fábrica —izquierda
  `identidad,botones`, centro `espacios`, derecha
  `medidores,red,volumen,reloj,ajustes`, agrupación continua— y se conserva
  tras reiniciar el panel.
  *Fallo corregido antes de marcar:* no se podía **vaciar** una zona. Una
  clave con valor vacío se trataba igual que una clave ausente y caía al
  valor de fábrica, así que la zona volvía a llenarse sola. Ahora se
  distingue "no está" de "está y vale vacío".
  *También:* los signos ‹ › ✕ medían ocho píxeles y eran imposibles de
  acertar con el ratón; ahora el dibujo sigue pequeño pero la zona sensible
  mide 22×22 (nueva pieza `Pulsable`).

---

## Bloque 2 — Sistema

- [ ] **2.1 Sonido** — tope de volumen, subida máxima por paso, protección
      contra picos.
- [ ] **2.2 Batería** — avisos bajo y crítico, aviso de carga completa,
      suspensión automática. *Sólo verificable en equipo real.*
- [ ] **2.3 Hora** — formato 24h / 12h am-pm / 12h AM-PM y segundos.
- [ ] **2.4 Teclado** — distribución y atajo de cambio.
- [ ] **2.5 Idioma de la interfaz**
- [ ] **2.6 Avisos sonoros** — batería y temporizador.

---

## Bloque 3 — Escritorio

- [ ] **3.1 Fondo: elegir archivo**
- [ ] **3.2 Fondo: buscar en Wallhaven** — integrado en el Centro de Control.
- [ ] **3.3 Claro / Oscuro** — requiere tema claro completo.
- [ ] **3.4 Paleta desde el fondo** — modos propios: Automático, Vivo, Suave,
      Un solo tono, Escala de grises.
- [ ] **3.5 Transparencia general**
- [ ] **3.6 Movimiento del fondo** — según espacio de trabajo, y zoom.
- [ ] **3.7 Panel Reloj de escritorio** — activar, colocar, estilo.
- [ ] **3.8 Panel Reloj: esfera** — marcas, números, manecillas, fecha.
- [ ] **3.9 Panel Nota** — texto libre en el escritorio.
- [ ] **3.10 Panel Tiempo** — requiere servicio de meteorología.

---

## Bloque 4 — Interfaz

- [ ] **4.1 Avisos** — servicio de notificaciones propio, duración, monitor.
- [ ] **4.2 Pantalla de bloqueo** — reloj, texto, desenfoque, seguridad.
- [ ] **4.3 Barra de aplicaciones (dock)** — activar, revelar, anclar.
- [ ] **4.4 Vista general** — rejilla de espacios, escala, filas y columnas.
- [ ] **4.5 Guía de atajos** — generada desde la configuración real de Hyprland.
- [ ] **4.6 Esquinas activas** — abrir paneles llevando el cursor a una esquina.
- [ ] **4.7 Avisos en pantalla** — volumen y brillo, duración.
- [ ] **4.8 Recorte de pantalla** — resaltar ventanas, guías, grosor.
- [ ] **4.9 Paneles laterales** — accesos rápidos y deslizadores.
- [ ] **4.10 Tipografías** — principal, números, títulos, monoespaciada,
      iconos, lectura. Con las fuentes incluidas en la imagen.

---

## Bloque 5 — Servicios

- [ ] **5.1 Frecuencia de medición de recursos**
- [ ] **5.2 Identificación de navegador** para servicios que la exigen.
- [ ] **5.3 Carpetas de destino** — capturas y grabaciones.
- [ ] **5.4 Buscador** — prefijos propios y buscador web configurable.
- [ ] **5.5 Meteorología** — ubicación, unidades, frecuencia.

---

## Bloque 6 — Avanzado

- [ ] **6.1 Aplicar paleta a la shell y utilidades**
- [ ] **6.2 Aplicar paleta a aplicaciones Qt**
- [ ] **6.3 Aplicar paleta a la terminal** — intensidad y contraste.
- [ ] **6.4 Restablecer valores de fábrica**
- [ ] **6.5 Exportar e importar configuración**
- [ ] **6.6 Actualizar un sistema ya instalado** — hoy no existe. `mpm`
      instala paquetes y gestiona kernels (`list`, `install`, `rollback`),
      pero no hay forma de llevar una versión nueva de MIKE OS a una máquina
      instalada sin copiar archivos a mano o reinstalar conservando `/home`.
      Hace falta un `mpm upgrade` que actualice el sistema base.

---

## Bloque 7 — Acerca de

- [ ] **7.1 Ficha de MIKE OS** — logo propio, versión, kernel, arquitectura.
- [ ] **7.2 Ficha del sistema** — init runit, gestor mpm, compositor Hyprland,
      intérprete bash, con sus versiones reales leídas del sistema.
- [ ] **7.3 Enlaces** — documentación, ayuda, reportar un fallo.
- [ ] **7.4 Créditos** — reconocer a los proyectos en los que nos apoyamos
      (Hyprland, Quickshell, BusyBox, runit), que es lo honesto.

---

## Bloque 8 — Gestor de paquetes

Trabajo pedido aparte del Centro de Control: MPM tenía que dejar de ser
inutilizable y pasar a ser el único gestor del sistema.

- [x] **8.1 Catálogo local en vez de una petición por dependencia** — el
      resolutor consultaba la API de búsqueda de archlinux.org una vez por
      paquete y otra por cada dependencia, en cascada. Firefox lanzaba
      cientos de peticiones encadenadas, tardaba más de cinco minutos y
      acababa fallando cuando el servidor cortaba por exceso de ritmo. Ahora
      se descargan las bases del repositorio una vez (unos 9 MB) y todo se
      resuelve en memoria. *Verificado: 212 paquetes para Firefox en 6 ms.*
- [x] **8.2 Dependencias virtuales** — `firefox` depende de `ttf-font` y
      `nautilus` de `libnautilus-extension.so`; ninguno existe como paquete.
      El resolutor anterior no entendía `provides`, los daba por perdidos y
      seguía: de ahí Firefox sin una sola fuente y Nautilus sin su librería.
      *Verificado: 8.570 nombres virtuales en el índice.*
- [x] **8.3 Sin límite de profundidad** — el tope de cuatro niveles truncaba
      cadenas largas y dejaba el resto de "cannot open shared object file".
- [x] **8.4 Descarga en lote y SHA256** — una sola llamada a curl en
      paralelo, y se comprueba el resumen que publica el repositorio. Cierra
      además la limitación de no verificar integridad por paquete.
- [x] **8.5 Fin del aviso de TLS de busybox wget** — el instalador ya no usa
      wget; donde sigue siendo el último recurso se filtra esa línea sin
      ocultar el resto de errores.
- [x] **8.6 Plan completo antes de instalar** — lista de dependencias nuevas
      con su tamaño, total de descarga, espacio adicional y confirmación. Nada
      de ir descubriendo dependencias con la instalación ya empezada.
- [x] **8.7 Comprobación de espacio libre** — antes de tocar la red.
- [x] **8.8 Una sola interfaz** — `m-arch-install` desaparece como orden
      suelta: pasa a ser `/usr/lib/mpm/resolver`, invocado por `mpm install`.
      Detección automática de fuente (archivo local, repositorio de MIKE OS,
      recetas, core/extra, Flathub) y prefijos `arch:` y `flathub:` para
      forzar una concreta.
- [x] **8.9 `mpm update` sin redescargas** — volvía a bajar el repositorio
      remoto entero aunque no hubiera cambiado nada; ahora compara el SHA256
      publicado con el del archivo que ya está en disco.
- [ ] **8.10 AUR** — necesita `makepkg` y base-devel compilando en la máquina
      del usuario. Es el backend más caro y el más frágil; va el último.
- [ ] **8.11 Paquetes `.deb`** — se extraen sin problema, pero sus
      dependencias usan nombres de Debian (`libgtk-3-0`) que no existen en el
      catálogo de Arch (`gtk3`). Instalables sí; resolución automática no, sin
      una tabla de equivalencias que siempre estaría incompleta.

**Pacman no está en MIKE OS.** No se compila ni aparece en `build.sh`; por eso
existía `m-arch-install`. Usarlo como backend significaría traer alpm entero
(base de datos de estado, ganchos, GPG) a una distribución construida desde
cero con busybox y runit. El motor propio hace ya lo mismo que hace pacman:
catálogo sincronizado, resolución local, `provides`, descarga en lote y
verificación por resumen.

---

## Bloque 9 — Escritorio: reacción inmediata

- [x] **9.1 La barra deja de reiniciarse en cada ajuste** — `shell.qml` era
      una plantilla: cambiar un ajuste reescribía el código fuente de la barra
      y había que matar quickshell para releerlo. Ese era el motivo de que la
      barra desapareciera y volviera a aparecer, y también de que el panel de
      ajustes se cerrara solo. Ahora lee `settings.json` en marcha y Qt
      revincula lo que dependa de él.
- [x] **9.2 Ajustes sin botón "Aplicar"** — cada cambio se guarda solo, con
      un margen de 400 ms para no escribir en cada píxel de un deslizador.
- [x] **9.3 Fondos de pantalla sin bloquear** — el catálogo descargaba las
      veinticuatro miniaturas con la ventana congelada antes de pintar nada.
      Ahora la cuadrícula sale al instante y cada miniatura se coloca al
      llegar. Las imágenes completas se siguen descargando sólo al elegir una.
- [x] **9.4 Copiar y pegar en la terminal** — MTerminal no vinculaba ningún
      atajo de portapapeles: `Ctrl+Shift+C`, `Ctrl+Shift+V`, `Shift+Insert` y
      `Ctrl+Shift+A` no existían. `Ctrl+C` sigue interrumpiendo, que es lo que
      debe hacer en una terminal.
- [ ] **9.5 npm y Firefox** — pendiente de reproducir en la máquina virtual
      con el resolutor nuevo antes de diagnosticar nada.


---

## Bloque 10 — Que no parezca hecho por una máquina

El sistema funcionaba y aun así se sentía barato. Mirando una captura con
calma, los motivos eran concretos, no una sensación: un solo color para todo,
iconos que eran caracteres de texto, párrafos de prosa dentro de la interfaz y
un gestor de paquetes que se contradecía a sí mismo en la misma pantalla.

- [x] **10.1 Cinco colores y un acento** — *11 sep 2026*
  `quickshell/Paleta.qml`, singleton que lee el mismo `settings.json` que la
  barra. Los dieciocho valores sueltos repartidos por los archivos se
  reducen a cinco (fondo, superficie, borde, texto, texto tenue) más cuatro
  derivados. **El acento sólo tiñe lo que está activo ahora mismo**; antes iba
  en títulos, iconos, bordes, teclas, el logo y las tarjetas a la vez, y
  cuando todo resalta no resalta nada.
  *Fallo corregido de paso:* `CtlButton` llevaba `#00d4ff` escrito dentro, así
  que los botones se quedaban en cian aunque eligieras otro acento.
  *Verificado:* con el acento en naranja, la barra, los medidores, el apartado
  activo y los botones cambian los cuatro; al volver a cian, vuelven.

- [x] **10.2 Iconos dibujados, no caracteres** — *11 sep 2026*
  `quickshell/Icono.qml`: treinta iconos trazados sobre una rejilla de 24×24,
  mismo grosor y misma escala, sólo con Canvas — ni fuentes de iconos, ni SVG,
  ni plugins de imagen que puedan faltar en la imagen final.
  Fuera los `◆ ◐ ⌥ ⓘ ⚙` y fuera los emoji del volumen, que **salían como un
  cuadrado vacío** porque no hay glifo para 🔊 en la fuente del sistema.
  La marca deja de ser un rombo genérico y pasa a ser un cursor de terminal.
  *Verificado por captura:* ningún cuadrado vacío en la barra.

- [x] **10.3 Deslizador de volumen** — *11 sep 2026*
  `quickshell/Deslizador.qml`. El control eran dos botones `−` y `+` en los
  extremos opuestos de setecientos píxeles, con la palabra "Volumen" en medio
  y **sin enseñar el nivel en ningún momento**. Ahora se arrastra, responde a
  la rueda y se lee de un vistazo. Añadido `m-volume set N`, porque un
  deslizador salta a un valor en vez de ir de cinco en cinco.

- [x] **10.4 Fuera la prosa de la interfaz** — *11 sep 2026*
  Eliminada la tarjeta "Personaliza MIKE OS a tu ritmo", que tranquilizaba en
  un párrafo sobre cuándo configurar las cosas. La bienvenida pasa de
  veinticuatro atajos en tres columnas a **cinco**, con el resto detrás de
  "Ver todos los atajos". Nadie lee veinticuatro atajos de golpe.
  *También:* `m-bluetooth` dejaba pasar los avisos de bluez por la salida
  normal, así que el panel enseñaba `No default controller available` —en
  inglés— **como si fuera un aparato emparejado**. Ahora sólo salen líneas de
  dispositivo de verdad, y hay `m-bluetooth estado` para preguntar sin tener
  que interpretar el texto de otra herramienta.

- [x] **10.5 Una sola salida en `mpm`** — *11 sep 2026*
  `mpm search ripgrep` imprimía los resultados de core/extra y, justo debajo,
  una cabecera nueva rematada con "No se encontraron paquetes para 'ripgrep'":
  el gestor se contradecía a sí mismo en la misma pantalla. Eran dos búsquedas
  independientes imprimiendo cada una por su cuenta. Ahora es una tabla, un
  recuento y una línea de qué hacer después.
  *Dos fallos más:* el resolutor recortaba las descripciones a 60 caracteres y
  las partía a mitad de palabra ("...Office docum"); y al instalar por receta
  se filtraba la ruta temporal interna
  (`/var/lib/mpm/tmp/mpm_recipe_ripgrep_JNNJHJ/source: OK`).

- [x] **10.6 Fondo sin circuito impreso** — *11 sep 2026*
  Un degradado con dos focos de luz muy tenues, sin motivo y sin texto, en
  lugar de la placa de circuitos, que es el cliché número uno de "esto lo
  generó una máquina".

---

## Bloque 11 — Cómo se verifica

- [x] **11.1 `tests/humo.sh`** — *11 sep 2026* · dieciocho comprobaciones:
  arranque, red, audio de punta a punta, escritorio, paquetes y **clics de
  verdad** sobre el Centro de Control y la rueda del volumen, inyectados por
  QMP. Cada una corresponde a un fallo que ya ocurrió. `./tests/humo.sh` sale
  con 0 si pasan todas.
  *Se ganó el sueldo el primer día:* de seis fallos en la primera pasada,
  cuatro eran del propio test y **dos eran bugs reales recién introducidos** —
  `mpm search` escribía en `/var/lib/mpm/tmp`, que es de root, así que un
  usuario normal recibía "Permission denied" al buscar un paquete.

- [x] **11.2 Socket QMP en `run-qemu.sh`** — *11 sep 2026* · es lo que permite
  mover el ratón y pulsar dentro de la máquina desde fuera, y por tanto
  comprobar que un botón hace lo que dice sin una persona delante.

- [x] **11.3 El proyecto está en git** — *11 sep 2026* · tres semanas de
  trabajo sin control de versiones. Al preparar el `.gitignore` se vio que
  excluía `quickshell/shell.qml` por una plantilla eliminada en el punto 9.1:
  **los 81 KB de la barra y el Centro de Control se habrían quedado fuera**.

- [x] **11.4 El build vuelve a funcionar desde cero** — *11 sep 2026* ·
  no se hacía un build limpio desde hacía semanas y estaba roto en dos sitios.
  BusyBox pasa `$(srctree)` y `$(CONFIG_PREFIX)` sin comillas, y kbuild se
  niega en seco a compilar desde una ruta con espacios. El proyecto se movió
  de `Proyectos 2026/mikeos` a `~/mikeos`.

---

## Bloque 12 — Que el sistema exista fuera de QEMU

Al mirar el instalador salió algo que no estaba en ningún sitio: **MIKE OS
nunca había arrancado solo**. `run-qemu.sh` le pasa el kernel en la mano
(`-kernel bzImage -initrd ...`), así que no había cadena de arranque en
absoluto, y `m-install` formateaba el disco entero sin tabla de particiones,
sin partición EFI y sin nada que arrancara. En un portátil de verdad eso es un
disco que la UEFI ni mira.

- [x] **12.1 Hardware real en el kernel** — *11 sep 2026*
  El kernel se construía con `make defconfig` más cuatro cosas de máquina
  virtual: **sin NVMe** (o sea, sin ver su propio disco), sin gráficos, sin
  WiFi, sin teclado. Añadidas ~150 claves para Surface Laptop 3/4 con AMD:
  NVMe, amdgpu con Display Core, Surface Aggregator (de donde cuelgan teclado,
  batería y ventiladores en una Surface), `PINCTRL_AMD` —sin él no hay
  interrupciones de touchpad—, audio ACP de Renoir, ath10k, y de propina
  Intel, MediaTek y Realtek para que la imagen no sirva para un solo modelo.
  *Verificado clave por clave sobre el `.config` resultante*, no dando por
  bueno que `merge_config` las aplicara: 19 no llegaban por dependencias que
  faltaban debajo, y una —`SND_SOC_AMD_RV_RT5682_MACH`— resultó ser de
  Chromebook (depende de `CROS_EC`), no de Surface.

- [x] **12.2 Firmware** — *11 sep 2026* · `/lib/firmware` no existía. Da igual
  el driver: la GPU y la WiFi no arrancan sin su binario. Se copia un
  subconjunto (no los 534 MiB del equipo de construcción) y se descomprime,
  porque el kernel no lee `.zst` sin `FW_LOADER_COMPRESS`.
  *De paso:* la pasada de `strip` recorría el rootfs entero y habría
  destrozado los blobs que son ELF por dentro. Ahora `/lib/firmware` queda
  fuera.

- [x] **12.3 Instalador que instala algo que arranca** — *11 sep 2026*
  GPT, partición EFI de 512 MiB en FAT32, raíz en **btrfs con subvolúmenes**
  (`@`, `@home`, `@instantaneas`) o ext4 a elegir, fstab por UUID y kernel en
  la partición EFI. **Sin gestor de arranque:** el kernel lleva
  `CONFIG_EFI_STUB`, así que él mismo es un ejecutable UEFI y se copia como
  `EFI/BOOT/BOOTX64.EFI`.

- [ ] **12.4 Live USB / ISO arrancable** — un medio que arranque en cualquier
      equipo y permita probar el sistema antes de instalarlo, con `m-install`
      a mano. Necesita `xorriso` (ISO híbrida con El Torito + imagen EFI).

- [ ] **12.5 Secure Boot** — las Surface vienen con Secure Boot activado y
      este kernel no lleva la firma de Microsoft. De momento se desactiva en
      la UEFI; firmarlo con clave propia (y matricularla) es otro punto.

---

## Bloque 13 — Actualizar todas las máquinas desde una

Que tú toques el código en tu equipo y quien quiera se lo lleve con
`mpm upgrade`. Buena parte ya estaba: `mpm` tiene `sources.list`,
`mpm source add`, descarga de `repo.json` y verificación SHA256.

- [ ] **13.1 Instantánea antes de actualizar** — con btrfs, `mpm upgrade` toma
      una instantánea del sistema antes de tocar nada, y `mpm rollback` vuelve
      a ella. Sustituye al copiado manual de archivos a
      `/var/lib/mpm/backups`, que duplica las escrituras de cada instalación y
      sólo protege lo que mpm conoce.
- [ ] **13.2 El sistema base, empaquetado** — `mcore`, `mike-desktop` y
      `mkshell` ya son `.mpk`. Falta `mikeos-base` (busybox, runit, bash) para
      que no quede nada fuera del alcance de una actualización.
- [ ] **13.3 El kernel, empaquetado** — un `.mpk` que deje el kernel nuevo en
      la partición EFI conservando el anterior, para poder volver si no
      arranca.
- [ ] **13.4 `scripts/publicar.sh`** — construye, sube al mini PC y regenera
      el índice. Una orden entre "he cambiado algo" y "ya se lo pueden bajar".
- [ ] **13.5 Paquetes firmados** — hoy se comprueba el SHA256 contra el
      índice, pero quien te suplante el servidor sirve su índice y su paquete
      y ambos cuadran. Una firma evita eso.

---

## Bloque 14 — mikeos.duckdns.org

La cara pública del sistema, en el mini PC de casa.

- [ ] **14.1 Página de inicio** — qué es MIKE OS, en qué se diferencia, y las
      cifras reales (arranque, memoria, tamaño).
- [ ] **14.2 Descarga directa** — la ISO más reciente, con su SHA256 al lado.
- [ ] **14.3 Guía de instalación** — desde grabar el USB hasta el primer
      arranque, incluido desactivar Secure Boot en una Surface.
- [ ] **14.4 Documentación** — lo que ya está en `docs/`, publicado y
      navegable, generado desde el repositorio y no copiado a mano.
- [ ] **14.5 Wiki** — páginas que se puedan editar sin tocar el repositorio.
- [ ] **14.6 Repositorio de paquetes** — el mismo dominio sirve
      `mpm/repo.json`, que es lo que consulta `mpm upgrade` (ver Bloque 13).

### El mini PC como backend del sistema

La idea de m1ke, y encaja: el mini PC de casa no sirve sólo los paquetes, es
**el servicio en línea de MIKE OS**. Todo lo de abajo es el mismo equipo y el
mismo dominio, así que no hay infraestructura nueva que mantener.

- [ ] **14.7 Índice de paquetes y descargas** — lo del 14.6, pero servido por
      Coolify con HTTPS, que es lo que ya hace con las demás aplicaciones.
- [ ] **14.8 Catálogo de fondos propio** — hoy los fondos vienen de Wallhaven,
      una API ajena que puede cambiar o cerrar. Un catálogo propio hace que
      «Fondo de pantalla» siga funcionando pase lo que pase.
- [ ] **14.9 Registro de equipos** — cada instalación dice su versión al
      actualizarse, de forma anónima. Sirve para saber si una actualización
      rompió algo antes de que alguien lo cuente.
- [ ] **14.10 Informes de fallo** — `m-doctor --enviar` sube el diagnóstico y
      devuelve un identificador que pegar en la wiki. Sólo cuando se pide.
- [ ] **14.11 Ajustes que siguen al usuario** — `settings.conf` guardado en el
      servidor para que un equipo nuevo quede como el anterior. Voluntario y
      apagado de fábrica: es la configuración de alguien, no telemetría.

---

## Estado

| Bloque | Puntos | Hechos |
|---|---|---|
| 0 · Cimientos | 5 | **5 ✓** |
| 1 · Barra | 22 | **18** |
| 2 · Sistema | 6 | 0 |
| 3 · Escritorio | 10 | 0 |
| 4 · Interfaz | 10 | 0 |
| 5 · Servicios | 5 | 0 |
| 6 · Avanzado | 6 | 0 |
| 7 · Acerca de | 4 | 0 |
| 8 · Gestor de paquetes | 11 | **9** |
| 9 · Reacción inmediata | 5 | **4** |
| 10 · Que no parezca de máquina | 6 | **6 ✓** |
| 11 · Cómo se verifica | 4 | **4 ✓** |
| 12 · Fuera de QEMU | 5 | **3** |
| 13 · Actualizaciones | 5 | 0 |
| 14 · mikeos.duckdns.org | 11 | 0 |
| **Total** | **115** | **49** |

---

## Incidencias

Lo que falló al verificar y sigue abierto. Se borra la línea cuando se
resuelve.

*(Ninguna abierta.)*

---

## Registro

| Fecha | Punto | Resultado |
|---|---|---|
| 31 ago 2026 | 0.1 Esquema de ajustes | Verificado — 14 claves, regeneración limpia |
| 31 ago 2026 | 0.2 Lector con validación | Verificado — resiste 6 claves corruptas |
| 31 ago 2026 | 0.3 Registro de módulos | Verificado — reordena desde el archivo |
| 31 ago 2026 | 0.4 Ventana del Centro de Control | Verificado — 8 apartados navegables |
| 31 ago 2026 | 0.5 Editar a mano | Verificado — abre settings.conf en vi |
| 31 ago 2026 | 1.1 Posición en 4 lados | Verificado — captura en top/bottom/left/right |
| 31 ago 2026 | 1.2 Forma de la barra | Verificado — las tres formas distintas |
| 31 ago 2026 | 1.3 Agrupación | Verificado — cápsulas sueltas vs compartida |
| 31 ago 2026 | 1.4 Bordes de pantalla | Verificado por píxel — 4 esquinas, 5 capas |
| 31 ago 2026 | 1.5 Tamaños | Verificado en mínimo y máximo |
| 31 ago 2026 | 1.6 Ocultar sola | Verificado con cursor real por QMP |
| 31 ago 2026 | 1.7 Transparencia | Verificado por píxel a 100/50/20 % |
| 31 ago 2026 | 1.8 Identidad | Verificado con clic real — abre Acerca de |
| 31 ago 2026 | 1.9 Espacios | Verificado con clic real — cambia de espacio |
| 31 ago 2026 | 1.10 Reloj | Verificado los cuatro formatos |
| 31 ago 2026 | 1.11 Volumen | Abierto — sin destino de audio |
| 11 sep 2026 | 1.11 Volumen | Verificado con rueda y clic reales — 95 % → 80 % |
| 11 sep 2026 | 10.1–10.6 Paso de diseño | Verificado por captura — acento sólo en lo activo |
| 11 sep 2026 | 11.1 Prueba de humo | 18 de 18 comprobaciones en verde |
| 31 ago 2026 | 1.12 Red | Verificado — eth0 real y clic al panel |
| 31 ago 2026 | 1.15 Medidores | Verificado con carga real — 0 % a 92 % |
| 31 ago 2026 | 1.17 Botones rápidos | Verificado — captura y teclado con clics |
| 31 ago 2026 | 1.19–1.22 Composición | Verificado — barra a medida que persiste |
