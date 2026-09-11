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
            } catch (e) {
                console.warn("ajustes ilegibles, se mantienen los anteriores:", e)
            }
        }
    }

    property string accent: ajuste("accent_color", "#00d4ff")

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
    readonly property color pillBgBase: "#12151d"
    property color pillBg: Qt.rgba(pillBgBase.r, pillBgBase.g, pillBgBase.b, barOpacity)
    property color pillBorder: Qt.rgba(0.141, 0.165, 0.220, Math.max(barOpacity, 0.35))

    // Autoocultar: la barra se retira y sólo vuelve al acercar el cursor al
    // borde. Con autoocultar no reserva espacio, o dejaría un hueco vacío.
    property bool barAutohide: ajuste("bar_autohide", false)
    property bool barVisible: !barAutohide

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
            Text {
                text: "◆"; color: root.accent
                font.pixelSize: root.vertical ? root.fontSize + 2 : root.fontSize - 1
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !root.vertical
                text: "MIKE"; color: "#ffffff"; font.bold: true
                font.pixelSize: root.fontSize
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !root.vertical
                text: "OS"; color: root.accent; font.bold: true
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
                                  : (encima.hovered ? Qt.lighter(root.pillBorder, 1.9) : "#3a3f4d")

                    Behavior on width  { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    Behavior on color  { ColorAnimation  { duration: 130 } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        visible: punto.actual
                        color: "#05070c"
                        font.pixelSize: Math.max(8, Math.round(root.fontSize * 0.8))
                        font.bold: true
                    }

                    HoverHandler { id: encima }
                    TapHandler { onTapped: Hyprland.dispatch("workspace " + modelData) }
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
                color: "#ffffff"; font.bold: true
                font.pixelSize: root.fontSize
            }
            Text {
                visible: root.vertical
                text: bloqueReloj.hora.split(":")[1] || ""
                color: "#ffffff"; font.bold: true
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
            Text {
                text: root.volNivel < 0 ? "🔇"
                    : (root.volMute ? "🔇" : (root.volNivel > 50 ? "🔊" : "🔉"))
                font.pixelSize: root.fontSize
                color: root.volNivel < 0 ? "#55606f" : "#c9d1dc"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.volNivel < 0 ? "sin audio"
                    : (root.volMute ? "mudo" : root.volNivel + "%")
                color: root.volNivel < 0 ? "#55606f" : "#ffffff"
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
            Text {
                text: root.redTipo === "wifi" ? "◍" : (root.redTipo === "cable" ? "⇄" : "⊘")
                color: root.redTipo === "none" ? "#55606f" : root.accent
                font.pixelSize: root.fontSize
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.redNombre
                color: root.redTipo === "none" ? "#55606f" : "#ffffff"
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
        Row {
            spacing: Math.round(root.fontSize * 0.9)

            Repeater {
                model: [
                    { etiqueta: "CPU", valor: root.cpuUso },
                    { etiqueta: "RAM", valor: root.memUso }
                ]
                Row {
                    spacing: 4
                    Text {
                        text: modelData.etiqueta
                        color: "#7d8794"
                        font.pixelSize: Math.max(8, root.fontSize - 3)
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // Barrita: se rellena con la carga y se pone ámbar cuando
                    // pasa de tres cuartos, para que un pico se note sin mirar
                    // el número.
                    Rectangle {
                        width: Math.round(root.fontSize * 2.2)
                        height: Math.max(4, Math.round(root.fontSize * 0.42))
                        radius: height / 2
                        color: "#2b3243"
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width * Math.min(100, Math.max(0, modelData.valor)) / 100
                            height: parent.height
                            radius: parent.radius
                            color: modelData.valor >= 75 ? "#ffb454" : root.accent
                            Behavior on width { NumberAnimation { duration: 250 } }
                        }
                    }
                    Text {
                        text: modelData.valor + "%"
                        color: "#ffffff"
                        font.pixelSize: root.fontSize
                        font.bold: true
                        // Ancho fijo: sin esto la barra se movía a cada
                        // actualización al pasar de 9 a 10 o de 99 a 100.
                        width: Math.round(root.fontSize * 2.4)
                        horizontalAlignment: Text.AlignRight
                        anchors.verticalCenter: parent.verticalCenter
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
        Row {
            spacing: Math.round(root.fontSize * 0.8)
            Repeater {
                model: ajuste("bar_buttons", ["captura", "teclado"])
                Text {
                    text: root.iconoBoton(modelData)
                    color: pulsable.hovered ? root.accent : "#c9d1dc"
                    font.pixelSize: root.fontSize + 2
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: pulsable; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.pulsarBoton(modelData) }
                }
            }
        }
    }

    Component {
        id: modAjustes
        Text {
            text: "⚙"
            font.pixelSize: root.fontSize + 1
            color: root.panelOpen ? "#05070c" : "#c9d1dc"
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
        { id: "medidores", nombre: "Medidores" },
        { id: "red",       nombre: "Red" },
        { id: "volumen",   nombre: "Volumen" },
        { id: "botones",   nombre: "Botones" },
        { id: "ajustes",   nombre: "Ajustes" }
    ]

    function nombreModulo(id) {
        for (var i = 0; i < modulosDisponibles.length; i++)
            if (modulosDisponibles[i].id === id) return modulosDisponibles[i].nombre
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
            case "captura": return "⛶"
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
        anchors {
            top:    root.vertical ? true : root.barPos !== "bottom"
            bottom: root.vertical ? true : root.barPos === "bottom"
            left:   root.vertical ? root.barPos === "left"  : true
            right:  root.vertical ? root.barPos === "right" : true
        }
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

        // --- Zona inicial (arriba o izquierda) ---
        Zona {
            modulos: ajuste("bar_left", ["identidad"])
            anchors.left: root.vertical ? undefined : parent.left
            anchors.leftMargin: root.vertical ? 0 : root.barMargin
            anchors.top: root.vertical ? parent.top : undefined
            anchors.topMargin: root.vertical ? root.barMargin : 0
            anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        }

        // --- Zona central ---
        Zona {
            modulos: ajuste("bar_center", ["espacios"])
            anchors.centerIn: parent
        }

        // --- Zona final (abajo o derecha) ---
        Zona {
            modulos: ajuste("bar_right", ["reloj", "ajustes"])
            anchors.right: root.vertical ? undefined : parent.right
            anchors.rightMargin: root.vertical ? 0 : root.barMargin
            anchors.bottom: root.vertical ? parent.bottom : undefined
            anchors.bottomMargin: root.vertical ? root.barMargin : 0
            anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        }
    }

    // Tira fina pegada al borde que detecta el cursor y trae la barra de
    // vuelta. Existe sólo con autoocultar activo; es un detector, no un panel,
    // así que no reserva espacio ni pinta nada.
    PanelWindow {
        visible: root.barAutohide && !root.barVisible
        anchors {
            top: root.barPos === "top"
            bottom: root.barPos === "bottom"
            left: root.barPos !== "right"
            right: root.barPos !== "left"
        }
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
    }

    readonly property var secciones: [
        { id: "vistazo",    nombre: "Vistazo",     icono: "◈" },
        { id: "sistema",    nombre: "Sistema",     icono: "▣" },
        { id: "barra",      nombre: "Barra",       icono: "▤" },
        { id: "escritorio", nombre: "Escritorio",  icono: "◨" },
        { id: "interfaz",   nombre: "Interfaz",    icono: "◐" },
        { id: "servicios",  nombre: "Servicios",   icono: "⚙" },
        { id: "avanzado",   nombre: "Avanzado",    icono: "⌥" },
        { id: "acercade",   nombre: "Acerca de",   icono: "ⓘ" }
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
            TapHandler { onTapped: root.panelOpen = false }
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
                        text: "Centro de Control"
                        color: "#ffffff"; font.pixelSize: 17; font.bold: true
                        Layout.fillWidth: true
                    }
                    CtlButton {
                        text: "Cerrar"; small: true
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
                            text: "✎  Editar a mano"
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
                                    Text {
                                        text: modelData.icono
                                        color: entrada.aqui ? "#05070c" : root.accent
                                        font.pixelSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: modelData.nombre
                                        color: entrada.aqui ? "#05070c" : "#c9d1dc"
                                        font.pixelSize: 12
                                        font.bold: entrada.aqui
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                HoverHandler { id: sobre }
                                TapHandler { onTapped: root.seccion = modelData.id }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            text: "MIKE OS 0.2.0"
                            color: "#55606f"; font.pixelSize: 10
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

                                Titulo { texto: "Sonido" }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    CtlButton { text: "−"; onClicked: volDown.running = true }
                                    Text {
                                        text: "Volumen"; color: "#c9d1dc"; font.pixelSize: 12
                                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                                    }
                                    CtlButton { text: "+"; onClicked: volUp.running = true }
                                }

                                Separador {}

                                RowLayout {
                                    Layout.fillWidth: true
                                    Titulo { texto: "Red"; Layout.fillWidth: true }
                                    CtlButton { text: "Buscar"; small: true; onClicked: wifiScan.running = true }
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
                                    color: root.redTipo === "none" ? "#55606f" : "#ffffff"
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
                                        color: "#c9d1dc"; font.pixelSize: 11
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    visible: wifiList.count === 0
                                    text: "Redes inalámbricas: no se detecta adaptador."
                                    color: "#55606f"; font.pixelSize: 10; font.italic: true
                                }

                                Separador {}

                                RowLayout {
                                    Layout.fillWidth: true
                                    Titulo { texto: "Bluetooth"; Layout.fillWidth: true }
                                    CtlButton { text: "Buscar"; small: true; onClicked: btScan.running = true }
                                }
                                Repeater {
                                    id: btList
                                    model: ListModel {}
                                    function refresh() { btListProc.running = true }
                                    delegate: Text {
                                        text: "▸ " + model.line
                                        color: "#c9d1dc"; font.pixelSize: 11
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    visible: btList.count === 0
                                    text: "No se detecta adaptador Bluetooth."
                                    color: "#55606f"; font.pixelSize: 10; font.italic: true
                                }

                                Separador {}

                                Titulo { texto: "Fondo de pantalla" }
                                CtlButton {
                                    text: "Elegir fondo..."
                                    onClicked: { root.panelOpen = false; panelFondos.abrir() }
                                }
                            }

                            // ===== SISTEMA =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "sistema"

                                Titulo { texto: "Teclado" }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true
                                    Etiqueta { texto: "Distribución" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "US"; small: true; active: settingsState.kbLayout === "us,es"; onClicked: settingsState.kbLayout = "us,es" }
                                        CtlButton { text: "ES"; small: true; active: settingsState.kbLayout === "es,us"; onClicked: settingsState.kbLayout = "es,us" }
                                    }
                                }

                                Separador {}

                                Titulo { texto: "Hora" }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: "Formato" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "24 h";     small: true; active: settingsState.clockFormat === "24h";     onClicked: settingsState.clockFormat = "24h" }
                                        CtlButton { text: "12 h am";  small: true; active: settingsState.clockFormat === "12h-min"; onClicked: settingsState.clockFormat = "12h-min" }
                                        CtlButton { text: "12 h AM";  small: true; active: settingsState.clockFormat === "12h-may"; onClicked: settingsState.clockFormat = "12h-may" }
                                    }

                                    Etiqueta { texto: "Mostrar segundos" }
                                    CtlButton {
                                        text: settingsState.clockSeconds ? "Sí" : "No"
                                        small: true
                                        active: settingsState.clockSeconds
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: settingsState.clockSeconds = !settingsState.clockSeconds
                                    }
                                }

                                Separador {}
                                Pendiente { texto: "Sonido, batería e idioma llegan en el Bloque 2." }
                            }

                            // ===== BARRA =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "barra"

                                Titulo { texto: "Posición" }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true
                                    Etiqueta { texto: "Lado de la pantalla" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "Arriba";    small: true; active: settingsState.barPosition === "top";    onClicked: settingsState.barPosition = "top" }
                                        CtlButton { text: "Abajo";     small: true; active: settingsState.barPosition === "bottom"; onClicked: settingsState.barPosition = "bottom" }
                                        CtlButton { text: "Izquierda"; small: true; active: settingsState.barPosition === "left";   onClicked: settingsState.barPosition = "left" }
                                        CtlButton { text: "Derecha";   small: true; active: settingsState.barPosition === "right";  onClicked: settingsState.barPosition = "right" }
                                    }

                                    Etiqueta { texto: "Forma" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "Pegada";   small: true; active: settingsState.barShape === "pegada";   onClicked: settingsState.barShape = "pegada" }
                                        CtlButton { text: "Isla";     small: true; active: settingsState.barShape === "isla";     onClicked: settingsState.barShape = "isla" }
                                        CtlButton { text: "Completa"; small: true; active: settingsState.barShape === "completa"; onClicked: settingsState.barShape = "completa" }
                                    }

                                    Etiqueta { texto: "Agrupación" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "Islas";    small: true; active: settingsState.barGrouping === "islas";    onClicked: settingsState.barGrouping = "islas" }
                                        CtlButton { text: "Continua"; small: true; active: settingsState.barGrouping === "continua"; onClicked: settingsState.barGrouping = "continua" }
                                    }

                                    Etiqueta { texto: "Bordes de pantalla" }
                                    CtlButton {
                                        text: settingsState.screenCorners ? "Redondeados" : "Rectos"
                                        small: true
                                        active: settingsState.screenCorners
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: settingsState.screenCorners = !settingsState.screenCorners
                                    }
                                }

                                Separador {}

                                Titulo { texto: "Tamaños" }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: "Alto de la barra" }
                                    Numero {
                                        valor: settingsState.barHeight
                                        minimo: 24; maximo: 96; paso: 4; sufijo: " px"
                                        onCambiado: settingsState.barHeight = nuevo
                                    }

                                    Etiqueta { texto: "Alto de los módulos" }
                                    Numero {
                                        valor: settingsState.barModuleHeight
                                        minimo: 18; maximo: 72; paso: 2; sufijo: " px"
                                        onCambiado: settingsState.barModuleHeight = nuevo
                                    }

                                    Etiqueta { texto: "Tamaño de letra" }
                                    Numero {
                                        valor: settingsState.barFontSize
                                        minimo: 8; maximo: 24; paso: 1; sufijo: " px"
                                        onCambiado: settingsState.barFontSize = nuevo
                                    }

                                    Etiqueta { texto: "Separación" }
                                    Numero {
                                        valor: settingsState.barSpacing
                                        minimo: 0; maximo: 24; paso: 2; sufijo: " px"
                                        onCambiado: settingsState.barSpacing = nuevo
                                    }

                                    Etiqueta { texto: "Opacidad" }
                                    Numero {
                                        valor: settingsState.barOpacity
                                        minimo: 20; maximo: 100; paso: 5; sufijo: " %"
                                        onCambiado: settingsState.barOpacity = nuevo
                                    }

                                    Etiqueta { texto: "Ocultar sola" }
                                    CtlButton {
                                        text: settingsState.barAutohide ? "Sí" : "No"
                                        small: true
                                        active: settingsState.barAutohide
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: settingsState.barAutohide = !settingsState.barAutohide
                                    }
                                }

                                Separador {}

                                Titulo { texto: "Módulos de la barra" }
                                Text {
                                    text: "‹ y › mueven dentro de la zona; ✕ quita de la barra."
                                    color: "#7d8794"; font.pixelSize: 11
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }

                                ZonaEditor {
                                    titulo: "Izquierda"; raiz: root
                                    lista: settingsState.zonaIzq
                                    onCambiada: settingsState.zonaIzq = nueva
                                }
                                ZonaEditor {
                                    titulo: "Centro"; raiz: root
                                    lista: settingsState.zonaCentro
                                    onCambiada: settingsState.zonaCentro = nueva
                                }
                                ZonaEditor {
                                    titulo: "Derecha"; raiz: root
                                    lista: settingsState.zonaDer
                                    onCambiada: settingsState.zonaDer = nueva
                                }

                                Separador {}

                                Titulo { texto: "Colocar un módulo" }
                                Repeater {
                                    model: root.modulosDisponibles
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: modelData.nombre
                                            color: "#c9d1dc"; font.pixelSize: 11
                                            Layout.fillWidth: true
                                        }
                                        CtlButton {
                                            text: "Izq"; small: true
                                            onClicked: {
                                                root.quitarDeTodas(modelData.id)
                                                settingsState.zonaIzq = root.anadirA(settingsState.zonaIzq, modelData.id)
                                            }
                                        }
                                        CtlButton {
                                            text: "Centro"; small: true
                                            onClicked: {
                                                root.quitarDeTodas(modelData.id)
                                                settingsState.zonaCentro = root.anadirA(settingsState.zonaCentro, modelData.id)
                                            }
                                        }
                                        CtlButton {
                                            text: "Der"; small: true
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

                                Titulo { texto: "Espacios y efectos" }
                                GridLayout {
                                    columns: 2; columnSpacing: 14; rowSpacing: 10
                                    Layout.fillWidth: true

                                    Etiqueta { texto: "Espacios de trabajo" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "−"; small: true; onClicked: if (settingsState.workspaceCount > 1) settingsState.workspaceCount-- }
                                        Text {
                                            text: settingsState.workspaceCount; color: "#ffffff"; font.pixelSize: 11
                                            width: 22; height: 22
                                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        }
                                        CtlButton { text: "+"; small: true; onClicked: if (settingsState.workspaceCount < 10) settingsState.workspaceCount++ }
                                    }

                                    Etiqueta { texto: "Desenfoque" }
                                    CtlButton {
                                        text: settingsState.blurEnabled ? "Sí" : "No"; small: true
                                        active: settingsState.blurEnabled
                                        Layout.alignment: Qt.AlignRight
                                        onClicked: settingsState.blurEnabled = !settingsState.blurEnabled
                                    }

                                    Etiqueta { texto: "Opacidad de la terminal" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "−"; small: true; onClicked: if (settingsState.opacity > 40) settingsState.opacity -= 2 }
                                        Text {
                                            text: settingsState.opacity + "%"; color: "#ffffff"; font.pixelSize: 11
                                            width: 34; height: 22
                                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        }
                                        CtlButton { text: "+"; small: true; onClicked: if (settingsState.opacity < 100) settingsState.opacity += 2 }
                                    }

                                    Etiqueta { texto: "Animaciones" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        CtlButton { text: "Sin"; small: true; active: settingsState.animSpeed === "instant"; onClicked: settingsState.animSpeed = "instant" }
                                        CtlButton { text: "Rápidas"; small: true; active: settingsState.animSpeed === "fast"; onClicked: settingsState.animSpeed = "fast" }
                                        CtlButton { text: "Suaves"; small: true; active: settingsState.animSpeed === "normal"; onClicked: settingsState.animSpeed = "normal" }
                                    }

                                    Etiqueta { texto: "Color de acento" }
                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignRight
                                        Repeater {
                                            model: ["#00d4ff", "#ff6600", "#00e676", "#e91e63", "#ffca28"]
                                            Rectangle {
                                                width: 22; height: 22; radius: 11
                                                color: modelData
                                                border.width: settingsState.accentColor === modelData ? 2 : 0
                                                border.color: "#ffffff"
                                                TapHandler { onTapped: settingsState.accentColor = modelData }
                                            }
                                        }
                                    }
                                }
                            }

                            // ===== INTERFAZ =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.seccion === "interfaz"
                                Titulo { texto: "Interfaz" }
                                Pendiente { texto: "Avisos, pantalla de bloqueo, vista general y tipografías llegan en el Bloque 4." }
                            }

                            // ===== SERVICIOS =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.seccion === "servicios"
                                Titulo { texto: "Servicios" }
                                Pendiente { texto: "Frecuencia de medición, carpetas de destino y buscador llegan en el Bloque 5." }
                            }

                            // ===== AVANZADO =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.seccion === "avanzado"
                                Titulo { texto: "Avanzado" }
                                Pendiente { texto: "Aplicar la paleta a la shell, a las aplicaciones Qt y a la terminal llega en el Bloque 6." }
                            }

                            // ===== ACERCA DE =====
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                visible: root.seccion === "acercade"

                                Titulo { texto: "Distribución" }
                                RowLayout {
                                    spacing: 14
                                    Rectangle {
                                        width: 58; height: 58; radius: 14
                                        color: "#0d2b33"
                                        border.color: root.accent; border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: ">_"
                                            color: root.accent; font.pixelSize: 22; font.bold: true
                                        }
                                    }
                                    ColumnLayout {
                                        spacing: 3
                                        Text { text: "MIKE OS"; color: "#ffffff"; font.pixelSize: 18; font.bold: true }
                                        Text { text: "Versión 0.2.0 · x86_64"; color: "#8a94a3"; font.pixelSize: 11 }
                                    }
                                }

                                Separador {}

                                Titulo { texto: "Sistema" }
                                GridLayout {
                                    columns: 2; columnSpacing: 20; rowSpacing: 6
                                    Etiqueta { texto: "Arranque" }
                                    Dato { texto: "runit" }
                                    Etiqueta { texto: "Paquetes" }
                                    Dato { texto: "mpm" }
                                    Etiqueta { texto: "Compositor" }
                                    Dato { texto: "Hyprland" }
                                    Etiqueta { texto: "Intérprete" }
                                    Dato { texto: "bash" }
                                }

                                Separador {}

                                Titulo { texto: "Se apoya en" }
                                Text {
                                    text: "Hyprland · Quickshell · BusyBox · runit · Mesa"
                                    color: "#8a94a3"; font.pixelSize: 11
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
                        text: "Los cambios se guardan solos"
                        color: "#7a8090"; font.pixelSize: 11
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

    // Lectura periódica del volumen. Tres segundos bastan: es un indicador,
    // no un medidor, y consultar más a menudo sólo gasta CPU.
    Process {
        id: volLeer
        command: ["m-volume", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim()
                if (t === "mute") { root.volMute = true }
                else if (t.length > 0 && !isNaN(parseInt(t))) {
                    root.volMute = false
                    root.volNivel = parseInt(t)
                } else {
                    root.volNivel = -1
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
