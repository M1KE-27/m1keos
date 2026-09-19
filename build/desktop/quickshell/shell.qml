import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// La barra lee sus ajustes de ~/.config/mike/settings.json mientras está en
// marcha. Antes este archivo era una plantilla: m-apply-settings sustituía
// marcadores __XXX__, reescribía el código fuente de la barra y mataba
// quickshell para que se releyera. De ahí que cada cambio de ajuste hiciera
// desaparecer la barra y volver a aparecer. Ahora cambiar un ajuste sólo
// reescribe el JSON y Qt revincula lo que dependa de él: el cambio se ve en
// el sitio, sin parpadeo y sin reiniciar ningún proceso.
//
// ShellRoot (no Item): con Item como raíz, Quickshell lo trataba como
// ventana normal y Hyprland la tileaba junto al resto -- de ahí el
// rectángulo blanco enorme visible aunque panelOpen empezara en false.
ShellRoot {
    id: root

    property int activeWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    property bool panelOpen: false

    // Ajustes vivos. Cada propiedad de abajo se declara como una lectura de
    // este objeto, así que al reescribirse el archivo cambian todas a la vez
    // sin que haya que tocar nada más.
    property var aj: ({})

    // El valor por defecto va aquí y no sólo en m-apply-settings: si el
    // archivo falta, está a medio escribir o le falta una clave, la barra
    // tiene que salir igual en vez de quedarse en blanco.
    function ajuste(clave, porDefecto) {
        return (aj && aj[clave] !== undefined && aj[clave] !== null)
            ? aj[clave] : porDefecto
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/mike/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.aj = JSON.parse(text())
                // El Centro de Control guarda su propia copia editable y, en
                // cuanto se toca un control, deja de seguir al archivo para
                // siempre. Si algo más lo reescribe (m-settings desde la
                // consola, otra sesión, o el propio m-apply-settings al
                // normalizar un valor), el panel se quedaba enseñando lo de
                // antes y en el siguiente cambio lo volvía a escribir encima.
                // Volver a leerlo aquí lo mantiene contando la verdad.
                settingsState.sincronizar()
            } catch (e) {
                console.warn("ajustes ilegibles, se mantienen los anteriores:", e)
            }
        }
    }

    // El acento vive en Paleta, que lo lee del mismo settings.json. Así lo
    // comparten la barra, el Centro de Control y los botones, en vez de que
    // cada uno se lo lea (o se lo invente) por su cuenta.
    readonly property color accent: Paleta.acento

    // Lista de espacios de trabajo. Antes la generaba m-apply-settings como
    // "1, 2, 3, 4" y se cosía al código; ahora sale del número guardado, así
    // que añadir o quitar espacios se ve al momento.
    property var workspaceModel: {
        var n = ajuste("workspace_count", 4)
        var lista = []
        for (var i = 1; i <= n; i++) lista.push(i)
        return lista
    }

    // Métricas de la barra modular, todas desde settings.conf. La barra es
    // transparente y más alta que los módulos: esa diferencia es el aire que
    // deja ver el fondo de pantalla alrededor de cada isla.
    // Con la barra en un lateral, barHeight pasa a ser su grosor y los
    // módulos se apilan en columna. Es la misma lista: cambia la dirección.
    property bool vertical:   barPos === "left" || barPos === "right"
    // Forma de la barra:
    //   isla     - franja transparente, cada módulo es una cápsula suelta
    //   pegada   - fondo continuo pegado al borde, redondeado sólo por dentro
    //   completa - franja sólida de borde a borde, sin redondeos
    property string barShape: ajuste("bar_shape", "isla")
    property string barPos:   ajuste("bar_position", "top")
    // islas    - cada módulo con su cápsula
    // continua - los de una misma zona comparten cápsula, separados por línea
    property string barGrouping: ajuste("bar_grouping", "islas")
    // Esquinas redondeadas de pantalla: recortes decorativos en las cuatro
    // esquinas para que el escritorio no termine en pico.
    property bool screenCorners: ajuste("screen_corners", false)
    property int cornerRadius: 14
    property int barHeight:   ajuste("bar_height", 48)
    property int barMargin:   Math.max(2, Math.round(barHeight * 0.12))
    // Los tres tamaños se limitan entre sí, no sólo por su rango propio: un
    // módulo más alto que la barra, o una letra más alta que el módulo, se
    // salía del recuadro. Se recorta a lo que cabe en vez de dejarlo romper.
    property int pillHeight:  Math.min(ajuste("bar_module_height", 36), barHeight - 2 * barMargin)
    property int fontSize:    Math.min(ajuste("bar_font_size", 12), Math.max(7, pillHeight - 10))
    property int pillPadding: Math.round(fontSize * 2.1)
    // Los puntos de espacio de trabajo se derivan de la letra: con medidas
    // fijas, al subir el tamaño de fuente el número del espacio activo se
    // salía del punto y aparecía recortado por arriba y por abajo.
    property int wsPunto:  Math.max(6, Math.round(fontSize * 0.72))
    property int wsLargo:  Math.round(fontSize * 2.0)
    property int wsCorto:  Math.round(fontSize * 1.4)
    property int pillSpacing: ajuste("bar_spacing", 8)
    // Transparencia de la barra. Se aplica al fondo, no al módulo entero:
    // bajando la opacidad del elemento se irían también el texto y los
    // iconos, y la barra quedaría ilegible en vez de translúcida.
    property real barOpacity: ajuste("bar_opacity", 100) / 100
    readonly property color pillBgBase: Paleta.superficie
    property color pillBg: Qt.rgba(pillBgBase.r, pillBgBase.g, pillBgBase.b, barOpacity)
    property color pillBorder: Qt.rgba(Paleta.borde.r, Paleta.borde.g, Paleta.borde.b,
                                       Math.max(barOpacity, 0.35))

    // Autoocultar: la barra se retira y sólo vuelve al acercar el cursor al
    // borde. Con autoocultar no reserva espacio, o dejaría un hueco vacío.
    property bool barAutohide: ajuste("bar_autohide", false)
    // Adrede sin binding: más abajo se le asigna a mano al esconder y al
    // sacar la barra, y una asignación imperativa mata el binding para
    // siempre. Escrito como "!barAutohide", bastaba usar el autoocultar una
    // vez para que barVisible dejara de seguirlo: al desactivarlo después, la
    // barra podía quedarse escondida sin forma de recuperarla. El handler lo
    // devuelve a su sitio cada vez que cambia el ajuste.
    property bool barVisible: true
    onBarAutohideChanged: barVisible = !barAutohide

    // La versión del sistema, leída de /etc/os-release. Antes estaba escrita a
    // mano en dos sitios de este archivo, así que al publicar la 0.3.0 el
    // Centro de Control siguió diciendo 0.2.0. Ahora sale de donde toca.
    property string versionSistema: "—"
    FileView {
        path: "/etc/os-release"
        onLoaded: {
            var m = /VERSION="?([^"\n]+)"?/.exec(text())
            if (m) root.versionSistema = m[1]
        }
    }

    // --- Batería -----------------------------------------------------
    //
    // No existía. En una máquina virtual no hay batería y no se echa de menos;
    // en un portátil, no tener ni idea de cuánta queda significa que el equipo
    // se apaga de golpe a media faena. Y un apagado sin avisar en btrfs puede
    // dejar el sistema de archivos a medias.
    //
    // Se lee de /sys/class/power_supply, que es donde el kernel lo publica. Si
    // no hay batería (sobremesa, máquina virtual) el módulo no se dibuja: un
    // indicador de batería al 0% en un sobremesa sería peor que ninguno.
    property int bateriaPct: -1
    property string bateriaEstado: ""
    readonly property bool hayBateria: bateriaPct >= 0

    Process {
        id: leerBateria
        running: true
        command: ["sh", "-c",
            "for b in /sys/class/power_supply/BAT*; do " +
            "  [ -r \"$b/capacity\" ] || continue; " +
            "  printf '%s %s' \"$(cat $b/capacity)\" \"$(cat $b/status 2>/dev/null)\"; " +
            "  exit 0; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim()
                if (t === "") { raiz_sin_bateria(); return }
                var p = t.split(" ")
                root.bateriaPct = parseInt(p[0])
                root.bateriaEstado = p.length > 1 ? p[1] : ""
            }
        }
    }
    function raiz_sin_bateria() { root.bateriaPct = -1 }
    Timer {
        // Cada treinta segundos: la batería no cambia tan rápido como para
        // justificar despertar el disco más a menudo, y cada lectura que no
        // hace falta es batería gastada en mirar la batería.
        interval: 30000; running: true; repeat: true
        onTriggered: leerBateria.running = true
    }

    // Estado de la contraseña de la cuenta: "puesta", "debil", "sin-clave" o
    // "desconocida". Lo dice m-clave, que es quien puede leer /etc/shadow.
    property string estadoClave: "desconocida"
    Process {
        id: mirarClave
        running: true
        command: ["m-clave", "estado"]
        stdout: StdioCollector {
            onStreamFinished: root.estadoClave = text.trim() || "desconocida"
        }
    }
    Process { id: bloquearAhora; command: ["m-bloquear"] }
    // Apagar y reiniciar. Se llaman por ruta completa a propósito: así se coge
    // el /usr/bin/reboot de MIKE OS y no el applet de BusyBox, que bajo runit
    // no hace nada y encima sale diciendo que todo fue bien (ver m-apagado).
    Process { id: reiniciarEquipo; command: ["/usr/bin/reboot"] }
    Process { id: apagarEquipo;    command: ["/usr/bin/poweroff"] }
    // Poner la contraseña es interactivo (se teclea dos veces), así que va en
    // una terminal de verdad en vez de en un cuadro del panel: reimplementar
    // aquí la doble comprobación sería repetir lo que passwd ya hace bien.
    Process {
        id: abrirClave
        command: ["m-terminal", "-e", "sh", "-c",
                  "m-clave poner; echo; echo 'Pulsa Intro para cerrar.'; read x"]
        onExited: mirarClave.running = true
    }

    // ------------------------------------------------------------------
    // ENERGÍA
    // ------------------------------------------------------------------
    // El perfil (ahorro / equilibrado / máximo) y qué hace la tapa. Los dos
    // los guarda y aplica m-energia; aquí sólo se enseñan y se cambian.
    //
    // "energiaPuede" es la lista de lo que ESTE equipo soporta de verdad
    // (suspender, hibernar, portatil). Se pregunta en vez de suponerlo: un
    // menú que ofrece hibernar en un equipo sin swap suficiente promete algo
    // que va a terminar en un apagón con el trabajo dentro.
    property string perfilEnergia: "auto"
    property string tapaAccion: "pantalla"
    property var energiaPuede: []
    property string energiaEstado: ""
    readonly property bool esPortatil: energiaPuede.indexOf("portatil") >= 0

    Process {
        id: leerEnergia
        running: true
        command: ["sh", "-c", "m-energia perfil; echo '---'; m-energia tapa; echo '---'; m-energia puede"]
        stdout: StdioCollector {
            onStreamFinished: {
                var partes = text.split("---")
                if (partes.length >= 1) root.perfilEnergia = partes[0].trim() || "auto"
                if (partes.length >= 2) root.tapaAccion = partes[1].trim() || "pantalla"
                if (partes.length >= 3) {
                    var l = []
                    var lineas = partes[2].split("\n")
                    for (var i = 0; i < lineas.length; i++) {
                        var v = lineas[i].trim()
                        if (v !== "") l.push(v)
                    }
                    root.energiaPuede = l
                }
            }
        }
    }
    Process {
        id: leerEnergiaEstado
        command: ["m-energia", "estado"]
        stdout: StdioCollector { onStreamFinished: root.energiaEstado = text.trim() }
    }
    Process {
        id: ponerPerfil
        property string cual: "auto"
        command: ["m-energia", cual]
        onExited: { leerEnergia.running = true; leerEnergiaEstado.running = true }
    }
    Process {
        id: ponerTapa
        property string cual: "pantalla"
        command: ["m-energia", "tapa", cual]
        onExited: leerEnergia.running = true
    }
    Process { id: dormirAhora; command: ["m-energia", "suspender"] }
    Process { id: hibernarAhora; command: ["m-energia", "hibernar"] }

    // ------------------------------------------------------------------
    // CONTROLADORES
    // ------------------------------------------------------------------
    // El análisis completo del equipo: qué hay, en qué estado está cada cosa
    // y qué paquete le falta. Lo hace m-drivers, que es el mismo que responde
    // en la terminal: el panel y la terminal no pueden decir cosas distintas
    // porque salen de la misma orden.
    property var driversComp: []
    property var driversPaq: []
    property bool driversEscaneando: false
    property bool driversInstalando: false
    property string driversCuando: ""

    Process {
        id: escanearDrivers
        command: ["m-drivers", "--json"]
        onRunningChanged: if (running) root.driversEscaneando = true
        stdout: StdioCollector {
            onStreamFinished: {
                root.driversEscaneando = false
                try {
                    var d = JSON.parse(text)
                    root.driversComp = d.componentes || []
                    root.driversPaq = d.paquetes || []
                    root.driversCuando = Qt.formatDateTime(new Date(), "HH:mm:ss")
                } catch (e) {
                    root.driversComp = []
                    root.driversPaq = []
                    root.driversCuando = "el análisis falló"
                }
            }
        }
    }
    Process {
        id: instalarDrivers
        // En una terminal de verdad y no en silencio: instalar descarga cientos
        // de megas y puede pedir cosas. Esconder eso detrás de un botón que no
        // da señales es exactamente lo que hacía pensar que no pasaba nada.
        command: ["m-terminal", "-e", "sh", "-c",
                  "m-drivers --instalar; echo; echo 'Pulsa Intro para cerrar.'; read x"]
        onExited: escanearDrivers.running = true
    }
    Process {
        id: informeHardware
        command: ["m-terminal", "-e", "sh", "-c",
                  "m-hardware; echo; echo 'Pulsa Intro para cerrar.'; read x"]
    }

    // Distribución de teclado activa, para que el botón enseñe cuál es.
    property string kbActual: String(ajuste("kb_layout", "us,es")).split(",")[0]

    // Medidores del sistema, en porcentaje.
    property int cpuUso: 0
    property int memUso: 0
    property int metricsInterval: ajuste("metrics_interval", 3000)

    // Red: tipo (wifi/cable/none) y nombre, leídos del sistema.
    property string redTipo: "none"
    property string redNombre: "sin red"

    // Volumen: -1 significa "no hay destino de audio", que es distinto de 0.
    property int volNivel: -1
    property bool volMute: false

    // Reloj
    property bool clockSeconds: ajuste("clock_seconds", false)
    property string clockFormat: ajuste("clock_format", "24h")

    function horaActual() {
        var d = new Date()
        var f
        if (root.clockFormat === "12h-min")      f = root.clockSeconds ? "hh:mm:ss ap" : "hh:mm ap"
        else if (root.clockFormat === "12h-may") f = root.clockSeconds ? "hh:mm:ss AP" : "hh:mm AP"
        else                                     f = root.clockSeconds ? "HH:mm:ss"    : "HH:mm"
        return Qt.formatTime(d, f)
    }

    // ============================================================
    // BARRA MODULAR
    // ============================================================
    // Qué se pinta y en qué orden lo deciden tres listas de settings.conf
    // (bar_left / bar_center / bar_right), no el código. Añadir, quitar o
    // reordenar un módulo es cambiar una lista; el catálogo de abajo es lo
    // único que hay que tocar para dar de alta uno nuevo.

    // --- Catálogo de módulos --------------------------------------
    // Cada componente es el CONTENIDO del módulo. La isla que lo envuelve
    // (fondo, borde, redondeo) la pone la barra, para que la forma sea
    // coherente y agrupar módulos después sea sólo cuestión de envolver.

    Component {
        id: modIdentidad
        // En vertical no cabe "MIKE OS" escrito: queda el rombo, que ya es
        // la marca, en lugar de recortar el nombre o girarlo de lado.
        Row {
            spacing: 5
            Icono {
                nombre: "logo"
                color: Paleta.texto
                tamano: root.vertical ? root.fontSize + 4 : root.fontSize + 2
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !root.vertical
                text: Idioma.t("MIKE"); color: Paleta.texto; font.bold: true
                font.pixelSize: root.fontSize
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !root.vertical
                text: Idioma.t("OS"); color: root.accent; font.bold: true
                font.pixelSize: root.fontSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Component {
        id: modEspacios
        Grid {
            columns: root.vertical ? 1 : 99
            spacing: Math.max(3, Math.round(root.fontSize * 0.5))
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            Repeater {
                model: root.workspaceModel
                Rectangle {
                    id: punto
                    property bool actual: modelData === root.activeWorkspace
                    // Dentro de un Grid no se ancla al padre: el propio Grid
                    // coloca y alinea. El punto activo se estira en la
                    // dirección de la barra, no siempre a lo ancho.
                    width:  actual ? (root.vertical ? root.wsCorto : root.wsLargo)
                                   : (encima.hovered ? Math.round(root.wsPunto * 1.5) : root.wsPunto)
                    height: actual ? (root.vertical ? root.wsLargo : root.wsCorto)
                                   : (encima.hovered ? Math.round(root.wsPunto * 1.5) : root.wsPunto)
                    radius: Math.min(width, height) / 2
                    color: actual ? root.accent
                                  : (encima.hovered ? Qt.lighter(root.pillBorder, 1.9) : Paleta.borde)

                    Behavior on width  { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    Behavior on color  { ColorAnimation  { duration: 130 } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        visible: punto.actual
                        color: Paleta.sobreAcento
                        font.pixelSize: Math.max(8, Math.round(root.fontSize * 0.8))
                        font.bold: true
                    }

                    HoverHandler { id: encima }
                    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: Hyprland.dispatch("workspace " + modelData) }
                }
            }
        }
    }

    Component {
        id: modReloj
        // En vertical la hora no cabe en una línea, así que se parte: las
        // horas encima de los minutos, en lugar de girar el texto de lado.
        Column {
            id: bloqueReloj
            property string hora: root.horaActual()
            spacing: 0
            // Dentro de un Column no se ancla al padre: el Column coloca.
            // Anclar aquí dejaba el módulo entero sin pintar.

            Text {
                text: root.vertical ? bloqueReloj.hora.split(":")[0] : bloqueReloj.hora
                color: Paleta.texto; font.bold: true
                font.pixelSize: root.fontSize
            }
            Text {
                visible: root.vertical
                text: bloqueReloj.hora.split(":")[1] || ""
                color: Paleta.texto; font.bold: true
                font.pixelSize: root.fontSize
            }

            // Sin segundos basta con despertar al cambiar de minuto; con
            // segundos hay que ir cada segundo. Se ajusta solo según el
            // ajuste, en vez de repintar 60 veces por minuto siempre.
            Timer {
                interval: root.clockSeconds ? 1000
                                            : 60000 - (new Date().getSeconds() * 1000)
                running: true
                repeat: false
                onTriggered: {
                    bloqueReloj.hora = root.horaActual()
                    interval = root.clockSeconds ? 1000
                                                 : 60000 - (new Date().getSeconds() * 1000)
                    restart()
                }
            }
        }
    }

    // Volumen. Lee el nivel de verdad con "m-volume get"; si no hay destino
    // de audio, el comando falla y el módulo lo dice en vez de enseñar un
    // número inventado. Rueda para subir y bajar, clic para silenciar.
    Component {
        id: modVolumen
        Row {
            spacing: 5
            Icono {
                nombre: (root.volNivel < 0 || root.volMute) ? "volumen-mudo"
                      : (root.volNivel > 50 ? "volumen-alto" : "volumen-bajo")
                tamano: root.fontSize + 2
                color: root.volNivel < 0 ? Paleta.textoTenue : Paleta.texto
                anchors.verticalCenter: parent.verticalCenter
            }
            // En vertical no cabe: "sin audio" son 60 px de texto en una
            // barra de 48 y se salía de la pantalla. El icono ya distingue
            // mudo, bajo y alto, que es lo que se mira de un vistazo.
            Text {
                visible: !root.vertical
                text: root.volNivel < 0 ? Idioma.t("sin audio")
                    : (root.volMute ? "mudo" : root.volNivel + "%")
                color: root.volNivel < 0 ? Paleta.textoTenue : Paleta.texto
                font.pixelSize: root.fontSize
                font.bold: root.volNivel >= 0
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Red. Muestra lo que hay de verdad: nombre de la red WiFi si la hay,
    // o la interfaz de cable, o "sin red". Al pulsar abre el apartado de red
    // del Centro de Control.
    Component {
        id: modRed
        Row {
            spacing: 5
            Icono {
                nombre: root.redTipo === "wifi" ? "wifi"
                      : (root.redTipo === "cable" ? "cable" : "sin-red")
                color: root.redTipo === "none" ? Paleta.textoTenue : Paleta.texto
                tamano: root.fontSize + 2
                anchors.verticalCenter: parent.verticalCenter
            }
            // Igual que el volumen: el nombre de la red no cabe de lado. El
            // icono ya dice si hay wifi, cable o nada; el nombre está en el
            // Centro de Control.
            Text {
                visible: !root.vertical
                text: root.redNombre
                color: root.redTipo === "none" ? Paleta.textoTenue : Paleta.texto
                font.pixelSize: root.fontSize
                font.bold: root.redTipo !== "none"
                anchors.verticalCenter: parent.verticalCenter
                // Un nombre de red largo no debe estirar la barra entera.
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.fontSize * 12)
            }
        }
    }

    // Medidores de CPU y memoria. Datos reales de /proc, con una barrita de
    // progreso además del número: de un vistazo se ve la carga sin leer.
    Component {
        id: modMedidores
        // En horizontal van en fila, con etiqueta, barrita y número. En
        // vertical no cabe nada de eso de lado: los dos medidores se apilan,
        // la barrita desaparece y queda la etiqueta encima del número, que es
        // lo único que se lee en 48 px de ancho. Antes se salía de la pantalla.
        Grid {
            columns: root.vertical ? 1 : 99
            spacing: Math.round(root.fontSize * 0.9)
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            Repeater {
                model: [
                    { etiqueta: "CPU", valor: root.cpuUso },
                    { etiqueta: "RAM", valor: root.memUso }
                ]
                Grid {
                    columns: root.vertical ? 1 : 99
                    spacing: root.vertical ? 0 : 4
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    Text {
                        text: modelData.etiqueta
                        color: Paleta.textoTenue
                        font.pixelSize: Math.max(8, root.fontSize - 3)
                        font.bold: true
                    }
                    // Barrita: se rellena con la carga y se pone ámbar cuando
                    // pasa de tres cuartos, para que un pico se note sin mirar
                    // el número.
                    Rectangle {
                        visible: !root.vertical
                        width: Math.round(root.fontSize * 2.2)
                        height: Math.max(4, Math.round(root.fontSize * 0.42))
                        radius: height / 2
                        color: Paleta.borde
                        Rectangle {
                            width: parent.width * Math.min(100, Math.max(0, modelData.valor)) / 100
                            height: parent.height
                            radius: parent.radius
                            color: modelData.valor >= 75 ? Paleta.aviso : root.accent
                            Behavior on width { NumberAnimation { duration: 250 } }
                        }
                    }
                    Text {
                        text: modelData.valor + "%"
                        color: Paleta.texto
                        font.pixelSize: root.vertical
                                        ? Math.max(8, root.fontSize - 2) : root.fontSize
                        font.bold: true
                        // Ancho fijo: sin esto la barra se movía a cada
                        // actualización al pasar de 9 a 10 o de 99 a 100.
                        width: Math.round(root.fontSize * 2.4)
                        horizontalAlignment: root.vertical
                                             ? Text.AlignHCenter : Text.AlignRight
                    }
                }
            }
        }
    }

    // Botones rápidos. Sólo aparecen los que tienen función de verdad detrás:
    // la lista vive en settings.conf y el catálogo de abajo es lo único que
    // decide qué existe.
    Component {
        id: modBotones
        Grid {
            columns: root.vertical ? 1 : 99
            spacing: Math.round(root.fontSize * 0.8)
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            Repeater {
                model: root.ajuste("bar_buttons", ["captura", "teclado"])
                Text {
                    text: root.iconoBoton(modelData)
                    color: pulsable.hovered ? root.accent : Paleta.texto
                    font.pixelSize: root.fontSize + 2
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: pulsable; cursorShape: Qt.PointingHandCursor }
                    // El área sensible era el rectángulo del propio glifo: unos
                    // 14 píxeles de alto. Con un ratón se acierta; con el dedo
                    // en un touchpad, no. Se agranda sin mover nada de sitio.
                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        margin: 10
                        onTapped: root.pulsarBoton(modelData)
                    }
                }
            }
        }
    }

    // Batería. Sólo aparece si el equipo tiene una.
    Component {
        id: modBateria
        Row {
            spacing: 6
            visible: root.hayBateria

            // La pila se dibuja con su nivel dentro, no con un icono por cada
            // tramo: así el nivel se ve de un vistazo sin leer el número.
            Item {
                width: root.fontSize + 9
                height: root.fontSize
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    id: carcasa
                    width: parent.width - 2
                    height: parent.height - 4
                    y: 2
                    radius: 3
                    color: "transparent"
                    border.width: 1.4
                    border.color: root.bateriaPct <= 15 && root.bateriaEstado !== "Charging"
                                  ? Paleta.aviso : Paleta.texto
                    Rectangle {
                        // El relleno nunca baja de 2 px: al 1% una barra de
                        // cero píxeles se ve igual que "sin batería".
                        width: Math.max(2, (carcasa.width - 5) * Math.max(0, Math.min(100, root.bateriaPct)) / 100)
                        height: carcasa.height - 5
                        x: 2.5; y: 2.5
                        radius: 1.5
                        color: root.bateriaEstado === "Charging" ? Paleta.ok
                             : (root.bateriaPct <= 15 ? Paleta.aviso : Paleta.texto)
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
                // El pinchito del polo positivo.
                Rectangle {
                    width: 2; height: parent.height - 10
                    x: parent.width - 2; y: 5
                    radius: 1
                    color: root.bateriaPct <= 15 && root.bateriaEstado !== "Charging"
                           ? Paleta.aviso : Paleta.texto
                }
            }
            Text {
                visible: !root.vertical
                text: root.bateriaPct + "%"
                color: root.bateriaPct <= 15 && root.bateriaEstado !== "Charging"
                       ? Paleta.aviso : Paleta.texto
                font.pixelSize: root.fontSize
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Component {
        id: modAjustes
        Icono {
            nombre: "ajustes"
            tamano: root.fontSize + 3
            color: root.panelOpen ? Paleta.sobreAcento : Paleta.texto
            rotation: root.panelOpen ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }

    // Devuelve el componente de un módulo por su nombre. Un nombre
    // desconocido en settings.conf simplemente no pinta nada, en vez de
    // romper la barra entera.
    function componenteDe(nombre) {
        switch (nombre) {
            case "identidad": return modIdentidad
            case "espacios":  return modEspacios
            case "reloj":     return modReloj
            case "volumen":   return modVolumen
            case "red":       return modRed
            case "medidores": return modMedidores
            case "bateria":   return modBateria
            case "botones":   return modBotones
            case "ajustes":   return modAjustes
        }
        return null
    }

    // Los módulos que actúan al pulsarlos lo declaran aquí, para que la isla
    // que los envuelve sepa si tiene que resaltarse y qué hacer.
    function esBoton(nombre) {
        return nombre === "ajustes" || nombre === "identidad"
            || nombre === "volumen" || nombre === "red"
    }

    // Los que responden a la rueda del ratón. Hoy sólo el volumen; un módulo
    // que no esté aquí deja pasar el gesto en vez de tragárselo.
    function tieneRueda(nombre) {
        return nombre === "volumen"
    }

    // delta > 0 es rueda hacia arriba. El volumen sube y baja de cinco en
    // cinco, igual que con los botones del panel, y se relee enseguida para
    // que el número siga a la rueda sin esperar al refresco de tres segundos.
    function rodarModulo(nombre, delta) {
        if (delta === 0) return
        if (nombre === "volumen") {
            if (root.volNivel < 0) return
            if (delta > 0) volUp.running = true
            else volDown.running = true
            volTrasRueda.restart()
        }
    }

    function pulsarModulo(nombre) {
        if (nombre === "ajustes") {
            root.panelOpen = !root.panelOpen
            if (root.panelOpen) { wifiList.refresh(); btList.refresh() }
        } else if (nombre === "red") {
            root.seccion = "vistazo"
            root.panelOpen = true
            wifiList.refresh()
        } else if (nombre === "volumen") {
            if (root.volNivel >= 0) volMute.running = true
        } else if (nombre === "identidad") {
            // El logo lleva a la ficha del sistema, que es lo que uno espera
            // al pulsar el nombre de la distribución.
            root.seccion = "acercade"
            root.panelOpen = true
        }
    }

    // --- Composición de la barra --------------------------------------
    readonly property var modulosDisponibles: [
        { id: "identidad", nombre: "Identidad" },
        { id: "espacios",  nombre: "Espacios" },
        { id: "reloj",     nombre: "Reloj" },
        { id: "bateria",   nombre: "Batería" },
        { id: "medidores", nombre: "Medidores" },
        { id: "red",       nombre: "Red" },
        { id: "volumen",   nombre: "Volumen" },
        { id: "botones",   nombre: "Botones" },
        { id: "ajustes",   nombre: "Ajustes" }
    ]

    function nombreModulo(id) {
        for (var i = 0; i < modulosDisponibles.length; i++)
            if (modulosDisponibles[i].id === id) return Idioma.t(modulosDisponibles[i].nombre)
        return id
    }

    function listaDe(txt) {
        return txt.split(",").filter(function (x) { return x.length > 0 })
    }

    function quitarDe(txt, indice) {
        var l = listaDe(txt); l.splice(indice, 1); return l.join(",")
    }

    // Mover dentro de la zona. Salirse por un extremo no hace nada: el salto
    // entre zonas se hace con los botones de abajo, que es más claro.
    function moverEn(txt, indice, paso) {
        var l = listaDe(txt)
        var d = indice + paso
        if (d < 0 || d >= l.length) return txt
        var t = l[indice]; l[indice] = l[d]; l[d] = t
        return l.join(",")
    }

    function anadirA(txt, id) {
        var l = listaDe(txt)
        if (l.indexOf(id) >= 0) return txt
        l.push(id)
        return l.join(",")
    }

    // Un módulo sólo puede estar en una zona, o saldría repetido en la barra.
    function quitarDeTodas(id) {
        var f = function (t) {
            return listaDe(t).filter(function (x) { return x !== id }).join(",")
        }
        settingsState.zonaIzq = f(settingsState.zonaIzq)
        settingsState.zonaCentro = f(settingsState.zonaCentro)
        settingsState.zonaDer = f(settingsState.zonaDer)
    }

    function iconoBoton(id) {
        switch (id) {
            // U+F030, la cámara de Nerd Fonts. Antes aquí había ⛶ (U+26F6),
            // que NO lo cubre ninguna fuente del sistema: salía un cuadrado
            // vacío en la barra.
            case "captura": return "\uf030"
            case "teclado": return root.kbActual === "es" ? "ES" : "US"
        }
        return "?"
    }

    function pulsarBoton(id) {
        if (id === "captura") capturaProc.running = true
        else if (id === "teclado") cambiarTeclado.running = true
    }

    function activo(nombre) {
        return nombre === "ajustes" && root.panelOpen
    }

    PanelWindow {
        id: bar
        // Los cuatro bordes se asignan de golpe, como un solo valor. Escritos
        // uno a uno, al pasar de arriba a un lateral había un instante con los
        // cuatro puestos, que en wlr-layer-shell significa "pantalla completa":
        // el compositor reconfiguraba la superficie con la zona reservada en el
        // borde equivocado y ahí se quedaba. Anchors es un value type, así que
        // esta forma es una única llamada y no existe estado intermedio.
        anchors: root.vertical
            ? ({ top: true,
                 bottom: true,
                 left:  root.barPos === "left",
                 right: root.barPos === "right" })
            : ({ left: true,
                 right: true,
                 top:    root.barPos !== "bottom",
                 bottom: root.barPos === "bottom" })
        // barHeight es el grosor de la franja. Se declara en las dos
        // dimensiones a propósito: la que va anclada por sus dos extremos
        // (izquierda+derecha en horizontal, arriba+abajo en vertical) la
        // decide el anclaje y este valor se ignora. Ponerla a cero colapsaba
        // la ventana y sólo cabía el primer módulo.
        implicitHeight: root.barHeight
        implicitWidth:  root.barHeight
        color: "transparent"
        visible: root.barVisible
        // Espacio reservado. Estaba a -1, que en wlr-layer-shell no significa
        // "automático" sino "no reserves nada y que nadie te mueva": de ahí
        // que todas las ventanas quedaran por debajo de la barra. Con la
        // altura real, el compositor deja ese hueco libre y ninguna ventana
        // se solapa. Con la barra oculta automáticamente no se reserva nada,
        // que es justo lo que se pide al activar esa opción.
        exclusiveZone: root.barAutohide ? 0 : root.barHeight
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Mientras el cursor esté sobre la barra, no se esconde.
        HoverHandler {
            id: sobreBarra
            onHoveredChanged: {
                if (hovered) ocultar.stop()
                else if (root.barAutohide) ocultar.restart()
            }
        }
        Timer {
            id: ocultar
            interval: 1200
            onTriggered: {
                if (root.barAutohide && !sobreBarra.hovered && !root.panelOpen)
                    root.barVisible = false
            }
        }
        // La cuenta atrás arranca también al aparecer, no sólo al salir el
        // cursor: si se asoma al borde y se va sin llegar a tocar la barra,
        // nunca había un "dejó de estar encima" y se quedaba visible para
        // siempre.
        Connections {
            target: root
            function onBarVisibleChanged() {
                if (root.barVisible && root.barAutohide) ocultar.restart()
            }
        }

        // Fondo de la franja. En "pegada" se desborda por el lado que toca la
        // pantalla para que ese par de esquinas redondeadas quede fuera de
        // vista: así el redondeo sólo se ve por dentro, que es lo que hace
        // que la barra parezca abrazada al borde.
        Rectangle {
            visible: root.barShape !== "isla"
            anchors.fill: parent
            anchors.topMargin:    root.barShape === "pegada" && root.barPos === "top"    ? -radius : 0
            anchors.bottomMargin: root.barShape === "pegada" && root.barPos === "bottom" ? -radius : 0
            anchors.leftMargin:   root.barShape === "pegada" && root.barPos === "left"   ? -radius : 0
            anchors.rightMargin:  root.barShape === "pegada" && root.barPos === "right"  ? -radius : 0
            color: root.pillBg
            radius: root.barShape === "pegada" ? 18 : 0
        }

        // Isla: envuelve el contenido de un módulo y le da forma.
        component Isla: Rectangle {
            id: isla
            property string modulo: ""
            property bool agrupada: false

            // Si el módulo de dentro decide no dibujarse, la isla tampoco.
            // Sin esto quedaba una cápsula vacía en la barra: le pasó al
            // módulo de batería, que se esconde solo cuando el equipo no tiene
            // ninguna, y dejaba un hueco con borde en mitad de la fila.
            visible: carga.item === null || carga.item.visible
            // La isla crece en la dirección de la barra y mantiene el grosor
            // en la perpendicular, para que todas queden alineadas.
            // En vertical el grosor lo manda la anchura disponible de la
            // barra, no pillHeight: pedir más de lo que cabe hacía que el
            // layout no colocara los módulos siguientes.
            implicitWidth:  root.vertical
                            ? root.barHeight - 2 * root.barMargin
                            : Math.max(carga.implicitWidth + root.pillPadding, root.pillHeight)
            implicitHeight: root.vertical
                            ? Math.max(carga.implicitHeight + 14, root.pillHeight)
                            : root.pillHeight
            radius: Math.min(width, height) / 2
            // Con la barra ya pintada, los módulos no repiten fondo: sólo se
            // marcan cuando están activos o bajo el cursor. Si la barra es
            // transparente, cada módulo es su propia cápsula.
            color: root.activo(isla.modulo) ? root.accent
                 : (raton.hovered && root.esBoton(isla.modulo) ? Qt.lighter(root.pillBg, 1.6)
                 : (root.barShape === "isla" && !isla.agrupada ? root.pillBg : "transparent"))
            border.width: (root.barShape === "isla" && !isla.agrupada)
                          || root.activo(isla.modulo) ? 1 : 0
            border.color: root.activo(isla.modulo) ? root.accent : root.pillBorder

            Behavior on color { ColorAnimation { duration: 130 } }

            Loader {
                id: carga
                anchors.centerIn: parent
                sourceComponent: root.componenteDe(isla.modulo)
            }

            HoverHandler { id: raton; enabled: root.esBoton(isla.modulo) }
            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                enabled: root.esBoton(isla.modulo)
                onTapped: root.pulsarModulo(isla.modulo)
            }
            WheelHandler {
                enabled: root.tieneRueda(isla.modulo)
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (evento) => root.rodarModulo(isla.modulo, evento.angleDelta.y)
            }
        }

        // Zona: agrupa los módulos de un extremo o del centro.
        //   islas    - cada módulo lleva su propia cápsula, con aire entre ellos
        //   continua - todos comparten una cápsula y se separan con una línea
        // Sólo aplica cuando la barra es transparente; con la barra ya pintada
        // (pegada/completa) ni la zona ni los módulos repiten fondo.
        component Zona: Rectangle {
            id: zona
            property var modulos: []
            readonly property bool agrupado: root.barGrouping === "continua"
                                             && root.barShape === "isla"

            visible: modulos.length > 0
            implicitWidth:  contenido.implicitWidth  + (agrupado ? 14 : 0)
            implicitHeight: contenido.implicitHeight + (agrupado ? 6 : 0)
            color: agrupado ? root.pillBg : "transparent"
            border.width: agrupado ? 1 : 0
            border.color: root.pillBorder
            radius: Math.min(width, height) / 2

            Grid {
                id: contenido
                anchors.centerIn: parent
                columns: root.vertical ? 1 : 99
                spacing: zona.agrupado ? 0 : root.pillSpacing
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter

                Repeater {
                    model: zona.modulos
                    delegate: Grid {
                        columns: root.vertical ? 1 : 99
                        spacing: 0
                        horizontalItemAlignment: Grid.AlignHCenter
                        verticalItemAlignment: Grid.AlignVCenter

                        Isla { modulo: modelData; agrupada: zona.agrupado }

                        // Línea divisoria entre módulos de una misma cápsula.
                        // No va tras el último: cerraría la zona por fuera.
                        Rectangle {
                            visible: zona.agrupado && index < zona.modulos.length - 1
                            width:  root.vertical ? root.pillHeight * 0.55 : 1
                            height: root.vertical ? 1 : root.pillHeight * 0.5
                            color: root.pillBorder
                        }
                    }
                }
            }
        }

        // --- Zonas de los extremos ---
        // Hay una variante por orientación en vez de una sola que gire, y no
        // es por gusto. Cuando un mismo item cambiaba de anclaje, QML
        // reevaluaba las seis bindings UNA A UNA, no de golpe, y entre medias
        // existía un instante con "top" y "verticalCenter" puestos a la vez.
        // Qt lee esa pareja como un estiramiento: calcula una altura y la fija
        // con setHeight(), lo que marca el alto como explícito PARA SIEMPRE.
        // Desde ahí el rectángulo dejaba de medirse por su implicitHeight
        // aunque el binding siguiera vivo: la barra se rompía al moverla a un
        // lado y seguía rota al devolverla arriba, porque la medida se había
        // quedado congelada y nada la recuperaba.
        //
        // Con un Loader por orientación, cada Zona nace con sus anclajes
        // definitivos y no los toca nunca. Al girar la barra la anterior se
        // destruye y la nueva se crea limpia, así que no hay estado que
        // corromper. La zona central nunca tuvo el fallo: usa centerIn, un
        // único anclaje que no cambia.

        // Extremo inicial, barra horizontal: pegado a la izquierda.
        Loader {
            active: !root.vertical
            anchors.left: parent.left
            anchors.leftMargin: root.barMargin
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Zona { modulos: root.ajuste("bar_left", ["identidad"]) }
        }
        // Extremo inicial, barra vertical: pegado arriba.
        Loader {
            active: root.vertical
            anchors.top: parent.top
            anchors.topMargin: root.barMargin
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: Zona { modulos: root.ajuste("bar_left", ["identidad"]) }
        }

        // --- Zona central ---
        Zona {
            modulos: root.ajuste("bar_center", ["espacios"])
            anchors.centerIn: parent
        }

        // Extremo final, barra horizontal: pegado a la derecha.
        Loader {
            active: !root.vertical
            anchors.right: parent.right
            anchors.rightMargin: root.barMargin
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Zona { modulos: root.ajuste("bar_right", ["reloj", "ajustes"]) }
        }
        // Extremo final, barra vertical: pegado abajo.
        Loader {
            active: root.vertical
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.barMargin
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: Zona { modulos: root.ajuste("bar_right", ["reloj", "ajustes"]) }
        }
    }

    // Tira fina pegada al borde que detecta el cursor y trae la barra de
    // vuelta. Existe sólo con autoocultar activo; es un detector, no un panel,
    // así que no reserva espacio ni pinta nada.
    PanelWindow {
        visible: root.barAutohide && !root.barVisible
        // De golpe también, por lo mismo que la barra.
        anchors: ({ top:    root.barPos === "top",
                    bottom: root.barPos === "bottom",
                    left:   root.barPos !== "right",
                    right:  root.barPos !== "left" })
        implicitHeight: root.vertical ? 0 : 3
        implicitWidth:  root.vertical ? 3 : 0
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        HoverHandler {
            onHoveredChanged: if (hovered) root.barVisible = true
        }
    }

    // ============================================================
    // ESQUINAS DE PANTALLA
    // ============================================================
    // Cuatro ventanas de capa de 14x14, una por esquina, por encima de todo y
    // sin capturar el ratón. Se probó primero con una sola ventana a pantalla
    // completa y cuatro lienzos dentro, pero los recortes de abajo no se
    // colocaban: con una ventana por esquina, el compositor ya la pone donde
    // toca y no hay que resolver posiciones a mano.

    // Recorte: cuadrado negro menos un círculo centrado en el vértice
    // diagonalmente opuesto al pico que toca el borde de la pantalla.
    component Recorte: Canvas {
        property bool haciaDerecha: false   // el pico está a la derecha
        property bool haciaAbajo: false     // el pico está abajo
        anchors.fill: parent
        // Canvas pinta una sola vez al crearse: sin pedirlo explícitamente,
        // algunos de los cuatro no llegaban a dibujarse.
        Component.onCompleted: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = "#000000"
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath()
            ctx.arc(haciaDerecha ? 0 : width,
                    haciaAbajo   ? 0 : height,
                    width, 0, 2 * Math.PI)
            ctx.fill()
        }
    }

    PanelWindow {
        visible: root.screenCorners
        anchors { top: true; left: true }
        implicitWidth: root.cornerRadius
        implicitHeight: root.cornerRadius
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Recorte { haciaDerecha: false; haciaAbajo: false }
    }

    PanelWindow {
        visible: root.screenCorners
        anchors { top: true; right: true }
        implicitWidth: root.cornerRadius
        implicitHeight: root.cornerRadius
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Recorte { haciaDerecha: true; haciaAbajo: false }
    }

    PanelWindow {
        visible: root.screenCorners
        anchors { bottom: true; right: true }
        implicitWidth: root.cornerRadius
        implicitHeight: root.cornerRadius
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Recorte { haciaDerecha: true; haciaAbajo: true }
    }

    PanelWindow {
        visible: root.screenCorners
        anchors { bottom: true; left: true }
        implicitWidth: root.cornerRadius
        implicitHeight: root.cornerRadius
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Recorte { haciaDerecha: false; haciaAbajo: true }
    }

    // ============================================================
    // CENTRO DE CONTROL
    // ============================================================
    // Ventana propia con navegación lateral, en lugar del desplegable
    // colgado de la barra: los ajustes ya no caben en una columna estrecha.
    // Cada apartado se rellena en su punto del plan; los que aún no tienen
    // función detrás lo dicen abiertamente en vez de enseñar interruptores
    // que no hacen nada.

    property string seccion: "vistazo"

    // Estado editable del Centro de Control. Arranca con lo guardado; en
    // cuanto se toca un control, la asignación rompe el enlace y ese valor
    // pasa a mandar sobre el archivo.
    //
    // Ya no hay botón "Aplicar": cada cambio se guarda solo. Antes hacía
    // falta porque guardar significaba reiniciar la barra, y hacerlo en cada
    // clic era insufrible; ahora guardar es escribir un JSON que la barra
    // relee sola, así que el botón sólo añadía un paso de más.
    QtObject {
        id: settingsState

        // Un solo texto con todos los valores: QML no avisa de "cualquier
        // propiedad ha cambiado", pero sí de que esta cadena cambió.
        property string huella: [
            barPosition, workspaceCount, blurEnabled, opacity, animSpeed,
            accentColor, kbLayout, barShape, barGrouping, screenCorners,
            barHeight, barModuleHeight, barFontSize, barSpacing,
            zonaIzq, zonaCentro, zonaDer, barOpacity, barAutohide,
            clockFormat, clockSeconds
        ].join("|")

        // El primer cambio de huella es el propio archivo cargándose, no una
        // edición del usuario: guardarlo ahí sólo reescribiría lo mismo.
        property bool listo: false
        onHuellaChanged: if (listo) guardarAjustes.restart()
        property string barPosition: root.barPos
        property int workspaceCount: root.ajuste("workspace_count", 4)
        property bool blurEnabled: root.ajuste("blur_enabled", false)
        property int opacity: root.ajuste("terminal_opacity", 98)
        property string animSpeed: root.ajuste("animation_speed", "fast")
        property string accentColor: root.accent
        property string kbLayout: root.ajuste("kb_layout", "us,es")
        property string barShape: root.barShape
        property string barGrouping: root.barGrouping
        property bool screenCorners: root.screenCorners
        property int barHeight: root.barHeight
        property int barModuleHeight: root.ajuste("bar_module_height", 36)
        property int barFontSize: root.ajuste("bar_font_size", 12)
        property int barSpacing: root.pillSpacing
        // Las tres zonas como texto separado por comas, igual que en el
        // archivo: el compositor edita exactamente lo que se guarda.
        property string zonaIzq: root.ajuste("bar_left", ["identidad"]).join(",")
        property string zonaCentro: root.ajuste("bar_center", ["espacios"]).join(",")
        property string zonaDer: root.ajuste("bar_right", ["reloj", "ajustes"]).join(",")
        property int barOpacity: root.ajuste("bar_opacity", 100)
        property bool barAutohide: root.barAutohide
        property string clockFormat: root.clockFormat
        property bool clockSeconds: root.clockSeconds

        // Reescribe todo el estado con lo que dice el archivo. Se llama al
        // recargarlo. Si el valor ya coincide -- el caso normal, porque casi
        // siempre venimos de haberlo guardado nosotros -- no cambia la huella
        // y no se dispara otro guardado: no hay bucle.
        function sincronizar() {
            barPosition    = root.barPos
            workspaceCount = root.ajuste("workspace_count", 4)
            blurEnabled    = root.ajuste("blur_enabled", false)
            opacity        = root.ajuste("terminal_opacity", 98)
            animSpeed      = root.ajuste("animation_speed", "fast")
            accentColor    = root.accent
            kbLayout       = root.ajuste("kb_layout", "us,es")
            barShape       = root.barShape
            barGrouping    = root.barGrouping
            screenCorners  = root.screenCorners
            barHeight      = root.barHeight
            barModuleHeight = root.ajuste("bar_module_height", 36)
            barFontSize    = root.ajuste("bar_font_size", 12)
            barSpacing     = root.pillSpacing
            zonaIzq        = root.ajuste("bar_left", ["identidad"]).join(",")
            zonaCentro     = root.ajuste("bar_center", ["espacios"]).join(",")
            zonaDer        = root.ajuste("bar_right", ["reloj", "ajustes"]).join(",")
            barOpacity     = root.ajuste("bar_opacity", 100)
            barAutohide    = root.barAutohide
            clockFormat    = root.clockFormat
            clockSeconds   = root.clockSeconds
        }
    }

    // Los apartados del Centro de Control.
    //
    // "Interfaz", "Servicios" y "Avanzado" ESTABAN AQUÍ y no tenían dentro ni
    // un solo control: un título y una frase diciendo que llegarían más
    // adelante. Tres de los nueve apartados del panel eran una promesa rota
    // cada vez que alguien los pulsaba.
    //
    // Se quedan fuera hasta que tengan algo dentro. Un menú que no ofrece lo
    // que no existe es más honesto -- y más corto -- que uno que sí.
    readonly property var secciones: [
        { id: "vistazo",    nombre: "Vistazo",     icono: "vistazo" },
        { id: "sistema",    nombre: "Sistema",     icono: "sistema" },
        { id: "energia",    nombre: "Energía",     icono: "energia" },
        { id: "drivers",    nombre: "Controladores", icono: "drivers" },
        { id: "barra",      nombre: "Barra",       icono: "barra" },
        { id: "escritorio", nombre: "Escritorio",  icono: "escritorio" },
        { id: "bloqueo",    nombre: "Bloqueo",     icono: "bloqueo" },
        { id: "acercade",   nombre: "Acerca de",   icono: "info" }
    ]

    PanelWindow {
        id: centroControl
        visible: root.panelOpen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Fondo oscurecido: separa la ventana del escritorio y permite
        // cerrarla pulsando fuera, que es lo que se espera de un diálogo.
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.5
            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                // Sólo cierra si el clic cae FUERA de la ventana. El fondo
                // ocupa la pantalla entera, también por debajo del Centro de
                // Control, así que antes recibía igualmente cada clic de
                // dentro: elegir un apartado cambiaba de sección y acto
                // seguido cerraba el panel.
                onTapped: (punto) => {
                    var x = punto.scenePosition.x
                    var y = punto.scenePosition.y
                    if (x < ventana.x || x > ventana.x + ventana.width
                        || y < ventana.y || y > ventana.y + ventana.height)
                        root.panelOpen = false
                }
            }
        }

        Rectangle {
            id: ventana
            anchors.centerIn: parent
            width: Math.min(parent.width - 100, 940)
            height: Math.min(parent.height - 100, 640)
            color: root.pillBg
            border.color: root.pillBorder
            border.width: 1
            radius: 18

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                // ---------- Título ----------
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: Idioma.t("Centro de Control")
                        color: Paleta.texto; font.pixelSize: 17; font.bold: true
                        Layout.fillWidth: true
                    }
                    CtlButton {
                        text: Idioma.t("Cerrar"); small: true
                        onClicked: root.panelOpen = false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 16

                    // ---------- Navegación lateral ----------
                    // Ancho fijo por los tres lados: con sólo preferredWidth,
                    // los hijos con fillWidth empujaban la columna hasta
                    // comerse la ventana y dejar el contenido en un hilo.
                    ColumnLayout {
                        Layout.preferredWidth: 178
                        Layout.minimumWidth: 178
                        Layout.maximumWidth: 178
                        Layout.fillWidth: false
                        Layout.fillHeight: true
                        spacing: 4

                        CtlButton {
                            Layout.fillWidth: true
                            text: Idioma.t("Editar a mano")
                            icono: "editar"
                            onClicked: abrirAjustes.running = true
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.pillBorder }

                        Repeater {
                            model: root.secciones
                            Rectangle {
                                id: entrada
                                property bool aqui: root.seccion === modelData.id
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 16
                                color: aqui ? root.accent
                                     : (sobre.hovered ? Qt.lighter(root.pillBg, 1.7) : "transparent")
                                Behavior on color { ColorAnimation { duration: 110 } }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 9
                                    Icono {
                                        nombre: modelData.icono
                                        color: entrada.aqui ? Paleta.sobreAcento : Paleta.textoTenue
                                        tamano: 15
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: Idioma.t(modelData.nombre)
                                        color: entrada.aqui ? Paleta.sobreAcento : Paleta.texto
                                        font.pixelSize: 12
                                        font.bold: entrada.aqui
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                HoverHandler { id: sobre }
                                TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: root.seccion = modelData.id }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            text: Idioma.t("MIKE OS ") + root.versionSistema
                            color: Paleta.textoTenue; font.pixelSize: 10
                            Layout.leftMargin: 12
                        }
                    }

                    Rectangle { Layout.fillHeight: true; width: 1; color: root.pillBorder }

                    // ---------- Contenido ----------
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: contenido.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: contenido
                            width: parent.width
                            spacing: 18

                            // ===== VISTAZO =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 16
                                visible: root.seccion === "vistazo"

                                Titulo { texto: Idioma.t("Sonido") }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Icono {
                                        nombre: (root.volNivel < 0 || root.volMute)
                                                ? "volumen-mudo"
                                                : (root.volNivel > 50 ? "volumen-alto"
                                                                      : "volumen-bajo")
                                        tamano: 16
                                        color: root.volNivel < 0 ? Paleta.textoTenue : Paleta.texto
                                        // Icono de 16x16: demasiado pequeño para
                                        // un dedo. El margen lo agranda sin
                                        // tocar el dibujo.
                                        TapHandler {
                                            gesturePolicy: TapHandler.ReleaseWithinBounds
                                            margin: 8
                                            enabled: root.volNivel >= 0
                                            onTapped: volMute.running = true
                                        }
                                    }
                                    Deslizador {
                                        Layout.fillWidth: true
                                        activo: root.volNivel >= 0
                                        valor: Math.max(0, root.volNivel)
                                        onCambiado: (nuevo) => {
                                            root.volNivel = nuevo
                                            volFijar.command = ["m-volume", "set", String(nuevo)]
                                            volFijar.running = true
                                        }
                                    }
                                }
                                Pendiente {
                                    visible: root.volNivel < 0
                                    texto: Idioma.t("No hay ninguna salida de audio conectada.")
                                }

                                Separador {}

                                RowLayout {
                                    Layout.fillWidth: true
                                    Titulo { texto: Idioma.t("Red"); Layout.fillWidth: true }
                                    CtlButton { text: Idioma.t("Buscar"); small: true; onClicked: wifiScan.running = true }
                                }
                                // Conexión actual, sea del tipo que sea. El
                                // apartado sólo hablaba de WiFi y parecía que
                                // no había red aunque hubiera cable.
                                Text {
                                    text: root.redTipo === "none"
                                          ? "Sin conexión."
                                          : (root.redTipo === "cable"
                                             ? "Conectado por cable · " + root.redNombre
                                             : "Conectado a " + root.redNombre)
                                    color: root.redTipo === "none" ? Paleta.textoTenue : Paleta.texto
                                    font.pixelSize: 12
                                    font.bold: root.redTipo !== "none"
                                    Layout.fillWidth: true
                                }

                                Repeater {
                                    id: wifiList
                                    model: ListModel {}
                                    function refresh() { wifiListProc.running = true }
                                    delegate: Text {
                                        text: "▸ " + model.line
                                        color: Paleta.texto; font.pixelSize: 11
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    visible: wifiList.count === 0
                                    text: Idioma.t("Redes inalámbricas: no se detecta adaptador.")
                                    color: Paleta.textoTenue; font.pixelSize: 10; font.italic: true
                                }

                                Separador {}

                                RowLayout {
                                    Layout.fillWidth: true
                                    Titulo { texto: Idioma.t("Bluetooth"); Layout.fillWidth: true }
                                    CtlButton { text: Idioma.t("Buscar"); small: true; onClicked: btScan.running = true }
                                }
                                Repeater {
                                    id: btList
                                    model: ListModel {}
                                    function refresh() { btListProc.running = true }
                                    delegate: Text {
                                        text: "▸ " + model.line
                                        color: Paleta.texto; font.pixelSize: 11
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    visible: btList.count === 0
                                    text: Idioma.t("No se detecta adaptador Bluetooth.")
                                    color: Paleta.textoTenue; font.pixelSize: 10; font.italic: true
                                }

                                Separador {}

                                Titulo { texto: Idioma.t("Fondo de pantalla") }
                                CtlButton {
                                    text: Idioma.t("Elegir fondo...")
                                    onClicked: { root.panelOpen = false; panelFondos.abrir() }
                                }
                            }

                            // ===== SISTEMA =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "sistema"

                                Titulo { texto: Idioma.t("Teclado") }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true
                                    Etiqueta { texto: Idioma.t("Distribución") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: Idioma.t("US"); small: true; active: settingsState.kbLayout === "us,es"; onClicked: settingsState.kbLayout = "us,es" }
                                        CtlButton { text: Idioma.t("ES"); small: true; active: settingsState.kbLayout === "es,us"; onClicked: settingsState.kbLayout = "es,us" }
                                    }
                                }

                                Separador {}

                                Titulo { texto: Idioma.t("Hora") }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: Idioma.t("Formato") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: Idioma.t("24 h");     small: true; active: settingsState.clockFormat === "24h";     onClicked: settingsState.clockFormat = "24h" }
                                        CtlButton { text: Idioma.t("12 h am");  small: true; active: settingsState.clockFormat === "12h-min"; onClicked: settingsState.clockFormat = "12h-min" }
                                        CtlButton { text: Idioma.t("12 h AM");  small: true; active: settingsState.clockFormat === "12h-may"; onClicked: settingsState.clockFormat = "12h-may" }
                                    }

                                    Etiqueta { texto: Idioma.t("Mostrar segundos") }
                                    CtlButton {
                                        text: settingsState.clockSeconds ? Idioma.t("Sí") : Idioma.t("No")
                                        small: true
                                        active: settingsState.clockSeconds
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: settingsState.clockSeconds = !settingsState.clockSeconds
                                    }
                                }

                                Separador {}

                                // El idioma, que es lo que el instalador
                                // lleva prometiendo desde su primera
                                // pantalla: "You can change this later in the
                                // Control Centre". Aquí es donde dijo que
                                // estaría.
                                //
                                // El cambio se ve al instante y en toda la
                                // ventana: todo lo que se pinta pasa por T(),
                                // que depende de Idioma.actual, así que moverlo
                                // vuelve a evaluar cada enlace. Sin
                                // reiniciar la sesión, que es lo que suelen
                                // pedir los sistemas que hacen esto a medias.
                                Titulo { texto: Idioma.t("Idioma") }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: Idioma.t("Idioma") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton {
                                            text: "Español"; small: true
                                            active: Idioma.actual === "es"
                                            onClicked: Idioma.cambiar("es")
                                        }
                                        CtlButton {
                                            text: "English"; small: true
                                            active: Idioma.actual === "en"
                                            onClicked: Idioma.cambiar("en")
                                        }
                                    }
                                }
                                Pendiente {
                                    texto: Idioma.t("El sistema entero: esta ventana, la barra y la bienvenida.")
                                }

                                Separador {}
                                Pendiente { texto: Idioma.t("Sonido y batería llegan en el Bloque 2.") }
                            }

                            // ===== ENERGÍA =====
                            //
                            // Rendimiento máximo para quien lo quiera --- en
                            // un sobremesa no hay motivo para no tenerlo --- y
                            // en un portátil, además, elegir qué pasa al
                            // cerrar la tapa. No se decide por el usuario: se
                            // le ofrece sólo lo que su equipo sabe hacer.
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "energia"

                                Titulo { texto: Idioma.t("Perfil") }

                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: Idioma.t("Modo") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton {
                                            text: Idioma.t("Automático"); small: true
                                            active: root.perfilEnergia === "auto"
                                            onClicked: { ponerPerfil.cual = "auto"; ponerPerfil.running = true }
                                        }
                                        CtlButton {
                                            text: Idioma.t("Ahorro"); small: true
                                            active: root.perfilEnergia === "ahorro"
                                            onClicked: { ponerPerfil.cual = "ahorro"; ponerPerfil.running = true }
                                        }
                                        CtlButton {
                                            text: Idioma.t("Equilibrado"); small: true
                                            active: root.perfilEnergia === "rendimiento"
                                            onClicked: { ponerPerfil.cual = "rendimiento"; ponerPerfil.running = true }
                                        }
                                        CtlButton {
                                            text: Idioma.t("Máximo"); small: true
                                            active: root.perfilEnergia === "maximo"
                                            onClicked: { ponerPerfil.cual = "maximo"; ponerPerfil.running = true }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: Paleta.textoTenue
                                    font.pixelSize: 10
                                    text: root.perfilEnergia === "maximo"
                                        ? "El procesador no baja de frecuencia y nada se duerme: ni el USB, ni el PCI Express, ni el audio. Es lo más rápido que da este equipo. En un portátil sin cargador gasta bastante más."
                                        : root.perfilEnergia === "ahorro"
                                        ? "Todo lo que puede dormirse, duerme. Las escrituras al disco se agrupan. Menos batería gastada, algo más de latencia al despertar."
                                        : root.perfilEnergia === "rendimiento"
                                        ? "Frecuencia bajo demanda y disco siempre despierto. El punto medio, y lo que se usa con el cargador puesto."
                                        : root.esPortatil
                                        ? "Con el cargador puesto va en equilibrado; con batería, en ahorro. Se cambia solo al enchufar y desenchufar."
                                        : "Este equipo no tiene batería, así que automático ya significa rendimiento máximo: no hay nada que ahorrar."
                                }

                                Separador {}

                                Titulo { texto: Idioma.t("Estado") }
                                Text {
                                    Layout.fillWidth: true
                                    color: Paleta.texto
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    text: root.energiaEstado === "" ? Idioma.t("Pulsa «Actualizar» para leerlo.") : root.energiaEstado
                                }
                                CtlButton {
                                    text: Idioma.t("Actualizar"); small: true
                                    onClicked: leerEnergiaEstado.running = true
                                }

                                // Lo de la tapa sólo tiene sentido si hay tapa.
                                Separador { visible: root.esPortatil }
                                Titulo { texto: Idioma.t("Al cerrar la tapa"); visible: root.esPortatil }

                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true
                                    visible: root.esPortatil

                                    Etiqueta { texto: Idioma.t("Hacer") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton {
                                            text: Idioma.t("Apagar pantalla"); small: true
                                            active: root.tapaAccion === "pantalla"
                                            onClicked: { ponerTapa.cual = "pantalla"; ponerTapa.running = true }
                                        }
                                        CtlButton {
                                            text: Idioma.t("Suspender"); small: true
                                            visible: root.energiaPuede.indexOf("suspender") >= 0
                                            active: root.tapaAccion === "suspender"
                                            onClicked: { ponerTapa.cual = "suspender"; ponerTapa.running = true }
                                        }
                                        CtlButton {
                                            text: Idioma.t("Hibernar"); small: true
                                            visible: root.energiaPuede.indexOf("hibernar") >= 0
                                            active: root.tapaAccion === "hibernar"
                                            onClicked: { ponerTapa.cual = "hibernar"; ponerTapa.running = true }
                                        }
                                        CtlButton {
                                            text: Idioma.t("Nada"); small: true
                                            active: root.tapaAccion === "nada"
                                            onClicked: { ponerTapa.cual = "nada"; ponerTapa.running = true }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: root.esPortatil
                                    wrapMode: Text.WordWrap
                                    color: Paleta.textoTenue
                                    font.pixelSize: 10
                                    text: Idioma.t("La sesión se bloquea siempre al cerrar, hagas lo que hagas con el resto. ")
                                        + (root.energiaPuede.indexOf("suspender") >= 0
                                           ? "Suspender depende del firmware del equipo: pruébalo con la tapa abierta antes de fiarte de él en la mochila."
                                           : "Este equipo no ofrece suspender: su firmware no lo publica en /sys/power/state.")
                                        + " Con un monitor externo conectado no se hace nada, para poder usarlo cerrado."
                                }

                                Separador { visible: root.energiaPuede.indexOf("suspender") >= 0 }
                                Row {
                                    spacing: 8
                                    visible: root.energiaPuede.indexOf("suspender") >= 0
                                    CtlButton { text: Idioma.t("Suspender ahora"); onClicked: dormirAhora.running = true }
                                    CtlButton {
                                        text: Idioma.t("Hibernar ahora")
                                        visible: root.energiaPuede.indexOf("hibernar") >= 0
                                        onClicked: hibernarAhora.running = true
                                    }
                                }
                            }

                            // ===== CONTROLADORES =====
                            //
                            // El apartado que faltaba: mira TODO el equipo ---
                            // gráfica, red, Bluetooth, sonido, entrada, cámara,
                            // discos, procesador, batería --- y de cada cosa
                            // dice en qué estado está. No sólo "qué instalar":
                            // también qué está detectado pero muerto, que es un
                            // problema distinto y se arregla de otra forma.
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "drivers"

                                // Escanear al entrar, no al arrancar la barra:
                                // recorrer PCI, USB y dmesg cuesta, y no tiene
                                // sentido pagarlo en cada arranque de sesión
                                // para un apartado que casi nunca se abre.
                                onVisibleChanged: if (visible && root.driversComp.length === 0 && !root.driversEscaneando) escanearDrivers.running = true

                                Titulo { texto: Idioma.t("Este equipo") }

                                Row {
                                    spacing: 8
                                    CtlButton {
                                        text: root.driversEscaneando ? Idioma.t("Analizando…") : Idioma.t("Analizar de nuevo")
                                        onClicked: if (!root.driversEscaneando) escanearDrivers.running = true
                                    }
                                    CtlButton { text: Idioma.t("Informe completo"); onClicked: informeHardware.running = true }
                                }

                                Text {
                                    visible: root.driversCuando !== ""
                                    color: Paleta.textoTenue
                                    font.pixelSize: 10
                                    text: Idioma.t("Último análisis: ") + root.driversCuando
                                }

                                Text {
                                    visible: root.driversComp.length === 0 && !root.driversEscaneando
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: Paleta.textoTenue
                                    font.pixelSize: 11
                                    text: Idioma.t("Todavía no se ha analizado nada.")
                                }

                                // La lista, agrupada por categoría. El
                                // encabezado se dibuja cuando cambia respecto
                                // a la fila anterior.
                                Repeater {
                                    model: root.driversComp
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            visible: index === 0 || root.driversComp[index - 1].categoria !== modelData.categoria
                                            text: modelData.categoria
                                            color: Paleta.textoTenue
                                            font.pixelSize: 10
                                            font.bold: true
                                            topPadding: index === 0 ? 0 : 8
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            // Un punto de color: verde va,
                                            // rojo no va, ámbar le falta algo.
                                            Rectangle {
                                                width: 8; height: 8; radius: 4
                                                Layout.alignment: Qt.AlignTop
                                                Layout.topMargin: 4
                                                color: modelData.estado === "ok"           ? "#00e676"
                                                     : modelData.estado === "sin-driver"   ? "#ff5252"
                                                     : modelData.estado === "sin-firmware" ? "#ffca28"
                                                     : modelData.estado === "apagado"      ? "#ffca28"
                                                     : Paleta.borde
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: Idioma.t(modelData.nombre)
                                                    color: Paleta.texto
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.detalle
                                                    color: Paleta.textoTenue
                                                    font.pixelSize: 10
                                                    wrapMode: Text.WordWrap
                                                }
                                            }

                                            Text {
                                                text: modelData.estado === "ok"           ? Idioma.t("funciona")
                                                    : modelData.estado === "sin-driver"   ? Idioma.t("sin driver")
                                                    : modelData.estado === "sin-firmware" ? Idioma.t("falta firmware")
                                                    : modelData.estado === "apagado"      ? Idioma.t("parado")
                                                    : modelData.estado === "ausente"      ? Idioma.t("no hay")
                                                    : modelData.estado
                                                color: Paleta.textoTenue
                                                font.pixelSize: 10
                                                Layout.alignment: Qt.AlignTop
                                                Layout.topMargin: 1
                                            }
                                        }
                                    }
                                }

                                Separador { visible: root.driversPaq.length > 0 }
                                Titulo { texto: Idioma.t("Recomendado para este equipo"); visible: root.driversPaq.length > 0 }

                                Repeater {
                                    model: root.driversPaq
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: Idioma.t(modelData.nombre)
                                            color: Paleta.texto
                                            font.pixelSize: 11
                                            font.bold: true
                                            Layout.preferredWidth: 140
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.motivo
                                            color: Paleta.textoTenue
                                            font.pixelSize: 10
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                CtlButton {
                                    visible: root.driversPaq.length > 0
                                    text: Idioma.t("Instalar lo recomendado")
                                    onClicked: instalarDrivers.running = true
                                }

                                Text {
                                    visible: root.driversPaq.length === 0 && root.driversComp.length > 0
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: Paleta.textoTenue
                                    font.pixelSize: 11
                                    text: Idioma.t("No falta nada: el sistema ya cubre este equipo.")
                                }
                            }

                            // ===== BARRA =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "barra"

                                Titulo { texto: Idioma.t("Posición") }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true
                                    Etiqueta { texto: Idioma.t("Lado de la pantalla") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: Idioma.t("Arriba");    small: true; active: settingsState.barPosition === "top";    onClicked: settingsState.barPosition = "top" }
                                        CtlButton { text: Idioma.t("Abajo");     small: true; active: settingsState.barPosition === "bottom"; onClicked: settingsState.barPosition = "bottom" }
                                        CtlButton { text: Idioma.t("Izquierda"); small: true; active: settingsState.barPosition === "left";   onClicked: settingsState.barPosition = "left" }
                                        CtlButton { text: Idioma.t("Derecha");   small: true; active: settingsState.barPosition === "right";  onClicked: settingsState.barPosition = "right" }
                                    }

                                    Etiqueta { texto: Idioma.t("Forma") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: Idioma.t("Pegada");   small: true; active: settingsState.barShape === "pegada";   onClicked: settingsState.barShape = "pegada" }
                                        CtlButton { text: Idioma.t("Isla");     small: true; active: settingsState.barShape === "isla";     onClicked: settingsState.barShape = "isla" }
                                        CtlButton { text: Idioma.t("Completa"); small: true; active: settingsState.barShape === "completa"; onClicked: settingsState.barShape = "completa" }
                                    }

                                    Etiqueta { texto: Idioma.t("Agrupación") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: Idioma.t("Islas");    small: true; active: settingsState.barGrouping === "islas";    onClicked: settingsState.barGrouping = "islas" }
                                        CtlButton { text: Idioma.t("Continua"); small: true; active: settingsState.barGrouping === "continua"; onClicked: settingsState.barGrouping = "continua" }
                                    }

                                    Etiqueta { texto: Idioma.t("Bordes de pantalla") }
                                    CtlButton {
                                        text: settingsState.screenCorners ? Idioma.t("Redondeados") : Idioma.t("Rectos")
                                        small: true
                                        active: settingsState.screenCorners
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: settingsState.screenCorners = !settingsState.screenCorners
                                    }
                                }

                                Separador {}

                                Titulo { texto: Idioma.t("Tamaños") }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: Idioma.t("Alto de la barra") }
                                    Numero {
                                        valor: settingsState.barHeight
                                        minimo: 24; maximo: 96; paso: 4; sufijo: " px"
                                        onCambiado: settingsState.barHeight = nuevo
                                    }

                                    Etiqueta { texto: Idioma.t("Alto de los módulos") }
                                    Numero {
                                        valor: settingsState.barModuleHeight
                                        minimo: 18; maximo: 72; paso: 2; sufijo: " px"
                                        onCambiado: settingsState.barModuleHeight = nuevo
                                    }

                                    Etiqueta { texto: Idioma.t("Tamaño de letra") }
                                    Numero {
                                        valor: settingsState.barFontSize
                                        minimo: 8; maximo: 24; paso: 1; sufijo: " px"
                                        onCambiado: settingsState.barFontSize = nuevo
                                    }

                                    Etiqueta { texto: Idioma.t("Separación") }
                                    Numero {
                                        valor: settingsState.barSpacing
                                        minimo: 0; maximo: 24; paso: 2; sufijo: " px"
                                        onCambiado: settingsState.barSpacing = nuevo
                                    }

                                    Etiqueta { texto: Idioma.t("Opacidad") }
                                    Numero {
                                        valor: settingsState.barOpacity
                                        minimo: 20; maximo: 100; paso: 5; sufijo: " %"
                                        onCambiado: settingsState.barOpacity = nuevo
                                    }

                                    Etiqueta { texto: Idioma.t("Ocultar sola") }
                                    CtlButton {
                                        text: settingsState.barAutohide ? Idioma.t("Sí") : Idioma.t("No")
                                        small: true
                                        active: settingsState.barAutohide
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: settingsState.barAutohide = !settingsState.barAutohide
                                    }
                                }

                                Separador {}

                                Titulo { texto: Idioma.t("Módulos de la barra") }
                                Text {
                                    text: Idioma.t("‹ y › mueven dentro de la zona; ✕ quita de la barra.")
                                    color: Paleta.textoTenue; font.pixelSize: 11
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }

                                ZonaEditor {
                                    titulo: Idioma.t("Izquierda"); raiz: root
                                    lista: settingsState.zonaIzq
                                    onCambiada: settingsState.zonaIzq = nueva
                                }
                                ZonaEditor {
                                    titulo: Idioma.t("Centro"); raiz: root
                                    lista: settingsState.zonaCentro
                                    onCambiada: settingsState.zonaCentro = nueva
                                }
                                ZonaEditor {
                                    titulo: Idioma.t("Derecha"); raiz: root
                                    lista: settingsState.zonaDer
                                    onCambiada: settingsState.zonaDer = nueva
                                }

                                Separador {}

                                Titulo { texto: Idioma.t("Colocar un módulo") }
                                Repeater {
                                    model: root.modulosDisponibles
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: Idioma.t(modelData.nombre)
                                            color: Paleta.texto; font.pixelSize: 11
                                            Layout.fillWidth: true
                                        }
                                        CtlButton {
                                            text: Idioma.t("Izq"); small: true
                                            onClicked: {
                                                root.quitarDeTodas(modelData.id)
                                                settingsState.zonaIzq = root.anadirA(settingsState.zonaIzq, modelData.id)
                                            }
                                        }
                                        CtlButton {
                                            text: Idioma.t("Centro"); small: true
                                            onClicked: {
                                                root.quitarDeTodas(modelData.id)
                                                settingsState.zonaCentro = root.anadirA(settingsState.zonaCentro, modelData.id)
                                            }
                                        }
                                        CtlButton {
                                            text: Idioma.t("Der"); small: true
                                            onClicked: {
                                                root.quitarDeTodas(modelData.id)
                                                settingsState.zonaDer = root.anadirA(settingsState.zonaDer, modelData.id)
                                            }
                                        }
                                    }
                                }
                            }

                            // ===== ESCRITORIO =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "escritorio"

                                Titulo { texto: Idioma.t("Espacios y efectos") }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: Idioma.t("Espacios de trabajo") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "−"; small: true; onClicked: if (settingsState.workspaceCount > 1) settingsState.workspaceCount-- }
                                        Text {
                                            text: settingsState.workspaceCount; color: Paleta.texto; font.pixelSize: 11
                                            width: 22; height: 22
                                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        }
                                        CtlButton { text: "+"; small: true; onClicked: if (settingsState.workspaceCount < 10) settingsState.workspaceCount++ }
                                    }

                                    Etiqueta { texto: Idioma.t("Desenfoque") }
                                    CtlButton {
                                        text: settingsState.blurEnabled ? Idioma.t("Sí") : Idioma.t("No"); small: true
                                        active: settingsState.blurEnabled
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: settingsState.blurEnabled = !settingsState.blurEnabled
                                    }

                                    Etiqueta { texto: Idioma.t("Opacidad de la terminal") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "−"; small: true; onClicked: if (settingsState.opacity > 40) settingsState.opacity -= 2 }
                                        Text {
                                            text: settingsState.opacity + "%"; color: Paleta.texto; font.pixelSize: 11
                                            width: 34; height: 22
                                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        }
                                        CtlButton { text: "+"; small: true; onClicked: if (settingsState.opacity < 100) settingsState.opacity += 2 }
                                    }

                                    Etiqueta { texto: Idioma.t("Animaciones") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: Idioma.t("Sin"); small: true; active: settingsState.animSpeed === "instant"; onClicked: settingsState.animSpeed = "instant" }
                                        CtlButton { text: Idioma.t("Rápidas"); small: true; active: settingsState.animSpeed === "fast"; onClicked: settingsState.animSpeed = "fast" }
                                        CtlButton { text: Idioma.t("Suaves"); small: true; active: settingsState.animSpeed === "normal"; onClicked: settingsState.animSpeed = "normal" }
                                    }

                                    Etiqueta { texto: Idioma.t("Color de acento") }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        Repeater {
                                            model: ["#00d4ff", "#ff6600", "#00e676", "#e91e63", "#ffca28"]
                                            Rectangle {
                                                width: 22; height: 22; radius: 11
                                                color: modelData
                                                border.width: settingsState.accentColor === modelData ? 2 : 0
                                                border.color: Paleta.texto
                                                TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; margin: 6; onTapped: settingsState.accentColor = modelData }
                                            }
                                        }
                                    }
                                }
                            }

                            // ===== INTERFAZ =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.seccion === "interfaz"
                                Titulo { texto: Idioma.t("Interfaz") }
                                Pendiente { texto: Idioma.t("Avisos, vista general y tipografías llegan en el Bloque 4. La pantalla de bloqueo tiene apartado propio.") }
                            }

                            // ===== BLOQUEO =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.seccion === "bloqueo"

                                Titulo { texto: Idioma.t("Pantalla de bloqueo") }

                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: Idioma.t("Contraseña de la cuenta") }
                                    Row {
                                        spacing: 8
                                        Layout.alignment: Qt.AlignRight
                                        Text {
                                            text: root.estadoClave === Idioma.t("puesta")  ? Idioma.t("Puesta")
                                                : root.estadoClave === "debil"    ? "Débil (DES)"
                                                : root.estadoClave === "sin-clave" ? "Sin contraseña"
                                                : "Sin averiguar"
                                            color: root.estadoClave === "puesta"
                                                   ? Paleta.texto : Paleta.aviso
                                            font.pixelSize: 11
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        CtlButton {
                                            text: root.estadoClave === Idioma.t("puesta") ? Idioma.t("Cambiar") : Idioma.t("Poner")
                                            small: true
                                            // Cerrar el panel ANTES de abrir la
                                            // terminal.
                                            //
                                            // El Centro de Control es una
                                            // superficie de capa a pantalla
                                            // completa y sin máscara: mientras
                                            // está abierta se traga todos los
                                            // clics y todas las teclas de la
                                            // pantalla entera. La terminal es
                                            // una ventana normal, así que salía
                                            // POR DEBAJO y no recibía nada:
                                            // escribías la contraseña y no
                                            // llegaba a ningún sitio. Los otros
                                            // dos botones que abren ventanas
                                            // (fondo de pantalla y bloquear) ya
                                            // cerraban el panel antes; éste se
                                            // quedó sin hacerlo.
                                            onClicked: {
                                                root.panelOpen = false
                                                abrirClave.running = true
                                            }
                                        }
                                    }

                                    Etiqueta { texto: Idioma.t("Bloquear ahora") }
                                    CtlButton {
                                        text: Idioma.t("Bloquear"); small: true
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: { root.panelOpen = false; bloquearAhora.running = true }
                                    }

                                    // Apagar y reiniciar.
                                    //
                                    // No existía NINGUNA forma de apagar el
                                    // equipo desde el escritorio: ni aquí, ni
                                    // en la barra, ni en ningún menú. La única
                                    // salida era una terminal, y allí "reboot"
                                    // tampoco funcionaba. Así que el sistema no
                                    // se podía apagar bien de ninguna manera.
                                    Etiqueta { texto: Idioma.t("Reiniciar el equipo") }
                                    CtlButton {
                                        text: Idioma.t("Reiniciar"); small: true
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: {
                                            root.panelOpen = false
                                            reiniciarEquipo.running = true
                                        }
                                    }

                                    Etiqueta { texto: Idioma.t("Apagar el equipo") }
                                    CtlButton {
                                        text: Idioma.t("Apagar"); small: true
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: {
                                            root.panelOpen = false
                                            apagarEquipo.running = true
                                        }
                                    }
                                }

                                // Se dice tal cual: una pantalla de bloqueo sobre
                                // una cuenta sin contraseña no protege de nada, y
                                // más vale saberlo antes que creerse protegido.
                                Pendiente {
                                    visible: root.estadoClave === "sin-clave"
                                    texto: Idioma.t("Esta cuenta no tiene contraseña, así que el bloqueo deja entrar sin preguntar. Ponle una aquí arriba.")
                                }
                                Pendiente {
                                    visible: root.estadoClave === "debil"
                                    texto: Idioma.t("La contraseña está cifrada con DES, que sólo mira sus 8 primeros caracteres. Vuelve a ponerla desde aquí para pasarla a sha512.")
                                }
                                Pendiente {
                                    texto: Idioma.t("Aviso: con la cuenta en el grupo «wheel», m-sudo da root sin pedir contraseña. El bloqueo protege de miradas, no de alguien con tiempo y teclado.")
                                }
                                Pendiente {
                                    texto: Idioma.t("El bloqueo automático por inactividad todavía no está: Quickshell 0.3.1 no expone el aviso de inactividad de Wayland. De momento se bloquea a mano con SUPER+L.")
                                }
                            }

                            // ===== SERVICIOS =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.seccion === "servicios"
                                Titulo { texto: Idioma.t("Servicios") }
                                Pendiente { texto: Idioma.t("Frecuencia de medición, carpetas de destino y buscador llegan en el Bloque 5.") }
                            }

                            // ===== AVANZADO =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.seccion === "avanzado"
                                Titulo { texto: Idioma.t("Avanzado") }
                                Pendiente { texto: Idioma.t("Aplicar la paleta a la shell, a las aplicaciones Qt y a la terminal llega en el Bloque 6.") }
                            }

                            // ===== ACERCA DE =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "acercade"

                                Titulo { texto: Idioma.t("Distribución") }
                                RowLayout {
                                    spacing: 14
                                    Rectangle {
                                        width: 58; height: 58; radius: 14
                                        color: Paleta.tenue(0.16)
                                        border.color: root.accent; border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: ">_"
                                            color: root.accent; font.pixelSize: 22; font.bold: true
                                        }
                                    }
                                    ColumnLayout {
                                        spacing: 3
                                        Text { text: Idioma.t("MIKE OS"); color: Paleta.texto; font.pixelSize: 18; font.bold: true }
                                        Text { text: Idioma.t("Versión ") + root.versionSistema + Idioma.t(" · x86_64"); color: Paleta.textoTenue; font.pixelSize: 11 }
                                    }
                                }

                                Separador {}

                                Titulo { texto: Idioma.t("Sistema") }
                                GridLayout {
                                    columns: 2; columnSpacing: 20; rowSpacing: 6
                                    Etiqueta { texto: Idioma.t("Arranque") }
                                    Dato { texto: Idioma.t("runit") }
                                    Etiqueta { texto: Idioma.t("Paquetes") }
                                    Dato { texto: Idioma.t("mpm") }
                                    Etiqueta { texto: Idioma.t("Compositor") }
                                    Dato { texto: Idioma.t("Hyprland") }
                                    Etiqueta { texto: Idioma.t("Intérprete") }
                                    Dato { texto: Idioma.t("bash") }
                                }

                                Separador {}

                                Titulo { texto: Idioma.t("Se apoya en") }
                                Text {
                                    text: Idioma.t("Hyprland · Quickshell · BusyBox · runit · Mesa")
                                    color: Paleta.textoTenue; font.pixelSize: 11
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                // ---------- Pie ----------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        id: estadoAjustes
                        text: ""
                        color: root.accent; font.pixelSize: 11
                        Layout.fillWidth: true
                    }
                    Text {
                        text: Idioma.t("Los cambios se guardan solos")
                        color: Paleta.textoTenue; font.pixelSize: 11
                    }
                }
            }
        }
    }

    // ============================================================
    // Procesos: todo delega en los mismos scripts que ya funcionan por
    // CLI (m-volume, m-wifi, m-bluetooth, m-apply-settings). El panel
    // solo dispara y muestra -- ninguna lógica de red/audio vive en QML.
    // ============================================================
    // Selector de fondos. Era una ventana GTK aparte que congelaba la
    // interfaz hasta tener las veinticuatro miniaturas; ahora es parte de la
    // misma shell y comparte su aspecto y su color de acento.
    Fondos {
        id: panelFondos
        acento: root.accent
        fondoPanel: root.pillBg
        bordePanel: root.pillBorder
    }

    // Permite abrirlo desde un atajo de teclado: Hyprland no puede hablar
    // con un objeto QML, pero sí ejecutar "quickshell ipc call fondos abrir".
    IpcHandler {
        target: "fondos"
        function abrir(): void { panelFondos.abrir() }
    }

    // Para que otras aplicaciones puedan abrir el Centro de Control. Lo usa
    // el botón de la pantalla de bienvenida, que antes era un párrafo
    // explicando dónde había que pulsar.
    IpcHandler {
        target: "ajustes"
        function abrir(): void {
            root.seccion = "vistazo"
            root.panelOpen = true
            wifiList.refresh()
        }

        // Abrir directamente un apartado. Lo usa la pantalla de bienvenida
        // para llevar a "Controladores" desde su ficha del equipo: contar con
        // palabras dónde hay que pulsar es el sustituto de un botón.
        function seccion(cual: string): void {
            var valida = false
            for (var i = 0; i < root.secciones.length; i++)
                if (root.secciones[i].id === cual) valida = true
            root.seccion = valida ? cual : "vistazo"
            root.panelOpen = true
            if (root.seccion === "drivers" && !root.driversEscaneando)
                escanearDrivers.running = true
        }

        // Cerrarlo desde fuera. Lo pide scripts/capturas.sh, que abre el
        // panel para fotografiar cada apartado y luego necesita el escritorio
        // limpio: el clic en el hueco de al lado dependía de que ahí no
        // hubiera ninguna ventana, y en cuanto una prueba abría la terminal
        // antes, ese clic caía dentro de la terminal y el panel se quedaba
        // abierto en todas las capturas siguientes.
        function cerrar(): void { root.panelOpen = false }

        // Para poder PREGUNTARLE a la barra en qué estado está.
        //
        // Las pruebas comprobaban si el Centro de Control se había abierto
        // comparando dos capturas de pantalla. No vale: la barra lleva un
        // reloj, así que dos capturas separadas por un segundo SIEMPRE salen
        // distintas y la comprobación decía que sí pasara lo que pasara.
        // Recortar la zona del reloj tampoco bastó.
        //
        // Adivinar el estado mirando píxeles era el problema. Esto lo dice.
        function estado(): string {
            return (root.panelOpen ? "abierto" : "cerrado") + " " + root.seccion
        }
    }

    // Lectura periódica del volumen. Tres segundos bastan: es un indicador,
    // no un medidor, y consultar más a menudo sólo gasta CPU.
    Process {
        id: volLeer
        command: ["m-volume", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "75", "75 mute", o nada si no hay destino de audio.
                var t = this.text.trim()
                var n = parseInt(t)
                if (t.length > 0 && !isNaN(n)) {
                    root.volNivel = n
                    root.volMute = t.indexOf("mute") >= 0
                } else {
                    root.volNivel = -1
                    root.volMute = false
                }
            }
        }
        onExited: if (exitCode !== 0) root.volNivel = -1
    }
    Timer {
        interval: 3000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: volLeer.running = true
    }
    Process { id: volMute; command: ["m-volume", "mute"]; onExited: volLeer.running = true }
    // Tras mover la rueda se relee el nivel, pero con un respiro: girando
    // rápido llegan muchos eventos seguidos y no tiene sentido lanzar una
    // lectura por cada uno.
    Timer { id: volTrasRueda; interval: 120; onTriggered: volLeer.running = true }

    Process { id: capturaProc; command: ["m-screenshot", "full"] }
    // Alternar teclado: cambia el orden de la lista y lo aplica. Se guarda,
    // así que sobrevive al reinicio de la sesión.
    Process {
        id: cambiarTeclado
        command: ["sh", "-c",
            "if grep -q 'kb_layout *= *\"us,es\"' ~/.config/mike/settings.conf; " +
            "then m-apply-settings set kb_layout=es,us; " +
            "else m-apply-settings set kb_layout=us,es; fi"]
    }

    // Medidores. m-metrics compara con su lectura anterior, así que no
    // necesita dormir dentro: cada consulta es inmediata.
    Process {
        id: medirProc
        command: ["m-metrics"]
        stdout: StdioCollector {
            onStreamFinished: {
                var c = this.text.trim().split("\t")
                if (c.length >= 2) {
                    root.cpuUso = parseInt(c[0]) || 0
                    root.memUso = parseInt(c[1]) || 0
                }
            }
        }
    }
    Timer {
        interval: root.metricsInterval
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: medirProc.running = true
    }

    // Estado de red. Cinco segundos: cambia poco y consultarlo cuesta un
    // proceso, así que no tiene sentido mirar más a menudo.
    Process {
        id: redLeer
        command: ["m-network", "bar"]
        stdout: StdioCollector {
            onStreamFinished: {
                var campos = this.text.trim().split("\t")
                if (campos.length >= 3) {
                    root.redTipo = campos[0]
                    root.redNombre = campos[0] === "none" ? campos[2] : campos[1]
                } else {
                    root.redTipo = "none"
                    root.redNombre = "sin red"
                }
            }
        }
    }
    Timer {
        interval: 5000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: redLeer.running = true
    }
    // "Editar a mano": abre settings.conf en una terminal. El archivo está
    // pensado para eso -- lleva los valores válidos comentados al lado.
    Process {
        id: abrirAjustes
        command: ["m-terminal", "-e", "vi ~/.config/mike/settings.conf"]
    }
    // El deslizador no sube y baja a pasos desde donde estuviera: salta al
    // valor que sueltas, así que necesita fijar un número, no un incremento.
    Process { id: volFijar; command: ["m-volume", "set", "50"]; onExited: volTrasRueda.restart() }
    Process { id: volUp; command: ["m-volume", "5"] }
    Process { id: volDown; command: ["m-volume", "-5"] }
    Process { id: wifiScan; command: ["m-wifi", "scan"]; onExited: wifiList.refresh() }
    Process { id: btScan; command: ["sh", "-c", "m-bluetooth scan 5"]; onExited: btList.refresh() }

    Process {
        id: wifiListProc
        command: ["m-wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                wifiList.model.clear()
                const lines = this.text.split("\n").filter(l => l.trim().length > 0)
                for (const l of lines) wifiList.model.append({ line: l.trim() })
            }
        }
    }
    Process {
        id: btListProc
        command: ["m-bluetooth", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                btList.model.clear()
                const lines = this.text.split("\n").filter(l => l.trim().length > 0)
                for (const l of lines) btList.model.append({ line: l.trim() })
            }
        }
    }

    // Espera a que el usuario deje de tocar antes de escribir. Sin esto, un
    // deslizador de altura lanzaría una escritura por cada píxel arrastrado.
    Timer {
        id: guardarAjustes
        interval: 400
        onTriggered: {
            applySettings.running = true
            estadoAjustes.text = "Guardando..."
        }
    }

    // La primera lectura del archivo mueve todos los enlaces de golpe. A
    // partir de ahí, cualquier cambio de huella sí viene de una edición.
    Timer {
        interval: 1200
        running: true
        onTriggered: settingsState.listo = true
    }

    Process {
        id: applySettings
        // Sólo se envían las claves que el panel controla. m-apply-settings
        // las actualiza en su sitio y respeta el resto del archivo: antes se
        // reescribía entero y cada "Aplicar" borraba la forma de la barra,
        // las listas de módulos y los ajustes del reloj.
        command: [
            "m-apply-settings", "set",
            "bar_position="     + settingsState.barPosition,
            "bar_shape="        + settingsState.barShape,
            "bar_grouping="     + settingsState.barGrouping,
            "screen_corners="   + (settingsState.screenCorners ? "true" : "false"),
            "bar_height="       + settingsState.barHeight,
            "bar_module_height="+ settingsState.barModuleHeight,
            "bar_font_size="    + settingsState.barFontSize,
            "bar_spacing="      + settingsState.barSpacing,
            "bar_left="         + settingsState.zonaIzq,
            "bar_center="       + settingsState.zonaCentro,
            "bar_right="        + settingsState.zonaDer,
            "bar_opacity="      + settingsState.barOpacity,
            "bar_autohide="     + (settingsState.barAutohide ? "true" : "false"),
            "clock_format="     + settingsState.clockFormat,
            "clock_seconds="    + (settingsState.clockSeconds ? "true" : "false"),
            "workspace_count="  + settingsState.workspaceCount,
            "blur_enabled="     + (settingsState.blurEnabled ? "true" : "false"),
            "terminal_opacity=" + settingsState.opacity,
            "animation_speed="  + settingsState.animSpeed,
            "accent_color="     + settingsState.accentColor,
            "kb_layout="        + settingsState.kbLayout
        ]
        stdout: StdioCollector {
            onStreamFinished: estadoAjustes.text = "Guardado"
        }
    }
}
