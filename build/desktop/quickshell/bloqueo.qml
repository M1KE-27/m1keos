//==============================================================================
// bloqueo.qml - La pantalla de bloqueo de MIKE OS.
//==============================================================================
//
// Usa WlSessionLock, que habla ext-session-lock-v1. Es la diferencia entre una
// pantalla de bloqueo y un adorno: con este protocolo el compositor no enseña
// el escritorio pase lo que pase, ni siquiera si este proceso se muere. Con
// una ventana normal por encima -- que es como se hacía antes de que existiera
// el protocolo -- basta con que el bloqueo casque para que quede todo a la
// vista.
//
// Qué hace distinto de hyprlock y de la pantalla de SDDM:
//
//   - Avisa del BLOQ MAYÚS. Es la causa número uno de "no me coge la
//     contraseña" y ninguno de los dos lo dice a las claras.
//   - Dice qué distribución de teclado está activa. Con dos idiomas
//     configurados, la contraseña se escribe distinta y no hay forma de
//     saberlo mirando.
//   - Si la cuenta NO tiene contraseña, lo dice y se deja abrir. Bloquear una
//     cuenta sin contraseña es encerrarte fuera de tu propio ordenador.
//   - El fondo es el mismo del escritorio, desenfocado: la pantalla de
//     bloqueo se parece al sistema en vez de a otro programa.
//   - Los intentos fallidos se cuentan y se ven.
//
// Lo lanza m-bloquear. La comprobación de la contraseña la hace m-autenticar,
// que es lo único que puede leer /etc/shadow.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: raiz

    // --- Estado -------------------------------------------------------
    property string clave: ""
    property bool comprobando: false
    property int fallos: 0
    property string aviso: ""
    // Una cuenta sin contraseña no se puede bloquear. Se detecta al arrancar
    // y, si es el caso, la pantalla lo explica y deja salir.
    property bool sinClave: false
    property bool mayusculas: false

    property string usuario: Quickshell.env("USER") || "mike"
    property string rutaFondo: ""

    readonly property color acento: "#00d4ff"
    readonly property color fondoBase: "#090b10"
    readonly property color texto: "#e6e9ef"
    readonly property color textoTenue: "#8b93a3"
    readonly property color error: "#ff5c68"

    function reloj() {
        var d = new Date()
        return Qt.formatDateTime(d, "HH:mm")
    }
    function fecha() {
        var dias = ["domingo", "lunes", "martes", "miércoles", "jueves",
                    "viernes", "sábado"]
        var meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
                     "julio", "agosto", "septiembre", "octubre", "noviembre",
                     "diciembre"]
        var d = new Date()
        return dias[d.getDay()] + ", " + d.getDate() + " de " + meses[d.getMonth()]
    }

    function intentar() {
        if (comprobando || clave.length === 0) return
        comprobando = true
        aviso = ""
        autenticar.running = true
    }

    // --- Procesos -----------------------------------------------------

    // La contraseña viaja por la entrada estándar, jamás como argumento: lo
    // que va en la línea de órdenes lo ve cualquiera con un "ps".
    Process {
        id: autenticar
        command: ["m-autenticar"]
        stdinEnabled: true
        onStarted: {
            write(raiz.clave + "\n")
            stdinEnabled = false
        }
        onExited: (codigo) => {
            raiz.comprobando = false
            if (codigo === 0) {
                raiz.clave = ""
                bloqueo.locked = false
                Qt.quit()
            } else if (codigo === 2) {
                raiz.sinClave = true
            } else if (codigo === 3) {
                raiz.aviso = "La cuenta está bloqueada. Entra por consola y usa «m-clave poner»."
            } else if (codigo === 4) {
                raiz.aviso = "No se ha podido comprobar la contraseña."
            } else {
                raiz.fallos++
                raiz.clave = ""
                raiz.aviso = raiz.fallos === 1
                    ? "Contraseña incorrecta."
                    : "Contraseña incorrecta (" + raiz.fallos + " intentos)."
                sacudida.restart()
            }
        }
    }

    // Estado de la cuenta al arrancar: si no hay contraseña puesta, más vale
    // saberlo antes de que alguien se quede fuera.
    Process {
        id: mirarCuenta
        running: true
        command: ["m-clave", "estado"]
        stdout: StdioCollector {
            onStreamFinished: raiz.sinClave = (text.trim() === "sin-clave")
        }
    }

    // El fondo del escritorio, para que la pantalla de bloqueo sea el mismo
    // sistema y no otra aplicación distinta.
    Process {
        id: mirarFondo
        running: true
        command: ["m-fondo", "actual"]
        stdout: StdioCollector {
            onStreamFinished: raiz.rutaFondo = text.trim()
        }
    }

    // La distribución activa. Con "es,us" configurado, la contraseña se
    // escribe distinta según cuál esté puesta y no hay manera de adivinarlo.
    property string distribucion: ""
    Process {
        id: mirarTeclado
        running: true
        command: ["sh", "-c",
            "hyprctl -j devices 2>/dev/null | grep -o '\"active_keymap\": *\"[^\"]*\"' | head -1 | cut -d'\"' -f4"]
        stdout: StdioCollector {
            onStreamFinished: raiz.distribucion = text.trim()
        }
    }

    // La hora vive en la raíz y las pantallas la miran. El temporizador no
    // puede tocar los textos directamente: están dentro de la superficie, que
    // es otro ámbito y se crea una vez POR PANTALLA. Escrito así, el reloj se
    // quedaba clavado en la hora a la que se bloqueó.
    property string horaAhora: reloj()
    property string fechaAhora: fecha()
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { raiz.horaAhora = raiz.reloj(); raiz.fechaAhora = raiz.fecha() }
    }

    // --- El bloqueo en sí ---------------------------------------------

    WlSessionLock {
        id: bloqueo
        locked: true

        // Una superficie por pantalla: en un portátil con monitor externo,
        // sin esto la segunda pantalla se queda enseñando el escritorio.
        WlSessionLockSurface {
            id: superficie
            color: raiz.fondoBase

            // Fondo: el del escritorio, desenfocado y oscurecido.
            //
            // El desenfoque se hace cargando la imagen a 96 px de ancho y
            // dejando que Qt la estire a pantalla completa con suavizado. No
            // es un capricho: se probó primero con MultiEffect, que es el
            // desenfoque "de verdad" de Qt, y bajo renderizado por software
            // -- una máquina virtual, un portátil sin drivers de vídeo, un
            // arranque en vivo antes de instalar nada -- no pintaba NADA y la
            // pantalla salía en negro. Justo los casos en los que este sistema
            // tiene que funcionar sí o sí.
            //
            // De paso sale casi gratis: se decodifican 96x54 píxeles en vez de
            // dos millones, así que el bloqueo aparece al instante.
            Image {
                id: fondo
                anchors.fill: parent
                source: raiz.rutaFondo ? "file://" + raiz.rutaFondo : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 96
                smooth: true
                asynchronous: true
                cache: true
                visible: status === Image.Ready
            }
            // Oscurecido. Sin esto, un fondo claro dejaría el texto ilegible.
            Rectangle {
                anchors.fill: parent
                color: raiz.fondoBase
                opacity: fondo.status === Image.Ready ? 0.55 : 1.0
            }

            // Sólo una pantalla enseña el formulario; las demás, la hora y
            // poco más. Si apareciera en todas habría varios campos de
            // contraseña y no se sabría en cuál se está escribiendo.
            readonly property bool principal:
                !superficie.screen || Quickshell.screens.length === 0
                || superficie.screen.name === Quickshell.screens[0].name

            Column {
                anchors.centerIn: parent
                spacing: 0

                // --- Hora ---
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: raiz.horaAhora
                    color: raiz.texto
                    font.pixelSize: 124
                    font.weight: Font.Light
                    font.letterSpacing: -3
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: raiz.fechaAhora
                    color: raiz.textoTenue
                    font.pixelSize: 19
                    topPadding: 4
                    // Aire de sobra antes del formulario: pegados, la inicial
                    // del avatar parecía parte de la fecha.
                    bottomPadding: 78
                }

                // --- Formulario ---
                Item {
                    visible: superficie.principal
                    width: 340
                    height: formulario.implicitHeight
                    anchors.horizontalCenter: parent.horizontalCenter

                    Column {
                        id: formulario
                        width: parent.width
                        spacing: 16

                        // Avatar: la inicial de la cuenta dentro de un círculo.
                        // No hay fotos de usuario en el sistema, y una inicial
                        // identifica la sesión mejor que un icono genérico.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 64; height: 64; radius: 32
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.rgba(raiz.acento.r, raiz.acento.g,
                                                  raiz.acento.b, 0.55)
                            Text {
                                anchors.centerIn: parent
                                text: raiz.usuario.charAt(0).toUpperCase()
                                color: raiz.acento
                                font.pixelSize: 26
                                font.bold: true
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: raiz.usuario
                            color: raiz.texto
                            font.pixelSize: 15
                            font.bold: true
                        }

                        // --- Caso sin contraseña ---
                        // Se explica y se deja salir. Encerrar a alguien fuera
                        // de su propio ordenador no es seguridad.
                        //
                        // Con el foco puesto aquí, Intro y Escape también
                        // abren: si sólo valiera el botón, un equipo sin ratón
                        // -- o con el touchpad todavía sin driver, que es justo
                        // el momento en que más falta hace -- se quedaría
                        // encerrado sin salida.
                        Item {
                            id: sinClaveCaja
                            visible: raiz.sinClave
                            width: parent.width
                            height: sinClaveCol.implicitHeight
                            focus: raiz.sinClave
                            Keys.onPressed: (e) => {
                                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter
                                    || e.key === Qt.Key_Escape || e.key === Qt.Key_Space) {
                                    bloqueo.locked = false
                                    Qt.quit()
                                }
                            }

                        Column {
                            id: sinClaveCol
                            width: parent.width
                            spacing: 10
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: "Esta cuenta no tiene contraseña, así que no hay nada que comprobar."
                                color: raiz.textoTenue
                                font.pixelSize: 13
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 150; height: 38; radius: 19
                                color: abrirRaton.hovered
                                       ? Qt.lighter(raiz.acento, 1.1) : raiz.acento
                                Text {
                                    anchors.centerIn: parent
                                    text: "Desbloquear"
                                    color: "#04121a"
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                                HoverHandler { id: abrirRaton; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: { bloqueo.locked = false; Qt.quit() }
                                }
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: "Pulsa Intro para abrir. Ponle una contraseña con «m-clave poner» y el bloqueo empezará a servir de algo."
                                color: Qt.rgba(raiz.textoTenue.r, raiz.textoTenue.g,
                                               raiz.textoTenue.b, 0.7)
                                font.pixelSize: 11
                            }
                        }
                        }

                        // --- Campo de contraseña ---
                        Item {
                            visible: !raiz.sinClave
                            width: parent.width
                            height: 46

                            Rectangle {
                                id: caja
                                anchors.fill: parent
                                radius: 23
                                // El desplazamiento de la sacudida va aquí:
                                // la caja está anclada a su hueco, así que no
                                // se le puede mover la x, pero sí empujarla
                                // con una transformación.
                                transform: Translate { id: empuje }
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1.5
                                border.color: raiz.fallos > 0 && raiz.aviso !== ""
                                    ? raiz.error
                                    : (entrada.activeFocus
                                       ? raiz.acento
                                       : Qt.rgba(1, 1, 1, 0.14))
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                TextInput {
                                    id: entrada
                                    anchors.fill: parent
                                    anchors.leftMargin: 22
                                    anchors.rightMargin: 52
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: raiz.texto
                                    font.pixelSize: 15
                                    // El punto grande se lee mejor que el
                                    // asterisco al contar cuántos llevas.
                                    echoMode: TextInput.Password
                                    passwordCharacter: "●"
                                    passwordMaskDelay: 0
                                    enabled: !raiz.comprobando
                                    focus: true
                                    text: raiz.clave
                                    onTextChanged: {
                                        raiz.clave = text
                                        if (raiz.aviso !== "") raiz.aviso = ""
                                    }
                                    onAccepted: raiz.intentar()
                                    Keys.onPressed: (e) => {
                                        if (e.key === Qt.Key_Escape) {
                                            raiz.clave = ""
                                            entrada.text = ""
                                            return
                                        }
                                        // Qt no expone el estado del Bloq
                                        // Mayús en ningún sitio. Sí se puede
                                        // deducir: si al pulsar una letra sale
                                        // en mayúscula SIN tener Shift -- o en
                                        // minúscula CON Shift -- es que está
                                        // puesto. Sólo sirve con letras, así
                                        // que lo demás se deja como estaba en
                                        // vez de apagar el aviso por error.
                                        var t = e.text
                                        if (t.length === 1 && t.toLowerCase() !== t.toUpperCase()) {
                                            var conShift = (e.modifiers & Qt.ShiftModifier) !== 0
                                            var esMayus = (t === t.toUpperCase())
                                            raiz.mayusculas = (esMayus !== conShift)
                                        }
                                    }
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: raiz.clave.length === 0 && !raiz.comprobando
                                    text: "Contraseña"
                                    color: Qt.rgba(raiz.textoTenue.r, raiz.textoTenue.g,
                                                   raiz.textoTenue.b, 0.8)
                                    font.pixelSize: 15
                                }

                                // Botón de entrar / indicador de comprobación
                                Item {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34; height: 34

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 17
                                        visible: !raiz.comprobando && raiz.clave.length > 0
                                        color: entrarRaton.hovered
                                               ? Qt.lighter(raiz.acento, 1.1) : raiz.acento
                                        Text {
                                            anchors.centerIn: parent
                                            text: "→"
                                            color: "#04121a"
                                            font.pixelSize: 17
                                            font.bold: true
                                        }
                                        HoverHandler { id: entrarRaton; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: raiz.intentar() }
                                    }

                                    // Girando mientras m-autenticar trabaja.
                                    // Sin esto parece que la pantalla se ha
                                    // colgado: comprobar tarda un segundo y
                                    // medio a propósito, para frenar a quien
                                    // pruebe contraseñas a lo bruto.
                                    Rectangle {
                                        id: girando
                                        anchors.centerIn: parent
                                        visible: raiz.comprobando
                                        width: 20; height: 20; radius: 10
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Qt.rgba(raiz.acento.r, raiz.acento.g,
                                                              raiz.acento.b, 0.25)
                                        Rectangle {
                                            width: 4; height: 4; radius: 2
                                            color: raiz.acento
                                            x: parent.width - 4; y: parent.height / 2 - 2
                                        }
                                        RotationAnimation on rotation {
                                            running: raiz.comprobando
                                            loops: Animation.Infinite
                                            from: 0; to: 360; duration: 900
                                        }
                                    }
                                }
                            }

                            // Sacudida al fallar. Es la señal que todo el
                            // mundo entiende sin leer nada.
                            SequentialAnimation {
                                id: sacudida
                                NumberAnimation { target: empuje; property: "x"; to: -9; duration: 55 }
                                NumberAnimation { target: empuje; property: "x"; to:  9; duration: 55 }
                                NumberAnimation { target: empuje; property: "x"; to: -6; duration: 55 }
                                NumberAnimation { target: empuje; property: "x"; to:  0; duration: 55 }
                            }
                        }

                        // --- Avisos ---
                        Text {
                            visible: raiz.aviso !== "" && !raiz.sinClave
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: raiz.aviso
                            color: raiz.error
                            font.pixelSize: 13
                        }

                        // BLOQ MAYÚS. La causa número uno de "la contraseña es
                        // esa y no entra", y ni hyprlock ni SDDM lo dicen.
                        Row {
                            visible: raiz.mayusculas && !raiz.sinClave
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6
                            Text {
                                text: "⇪"
                                color: "#ffb454"
                                font.pixelSize: 13
                            }
                            Text {
                                text: "Bloq Mayús está activado"
                                color: "#ffb454"
                                font.pixelSize: 13
                            }
                        }

                        // Distribución activa: con dos idiomas puestos, la
                        // contraseña se teclea distinta y no se ve cuál manda.
                        Text {
                            visible: raiz.distribucion !== "" && !raiz.sinClave
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Teclado: " + raiz.distribucion
                            color: Qt.rgba(raiz.textoTenue.r, raiz.textoTenue.g,
                                           raiz.textoTenue.b, 0.75)
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // Pie discreto: recuerda que el sistema sigue vivo detrás.
            Text {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 26
                text: "MIKE OS"
                color: Qt.rgba(raiz.textoTenue.r, raiz.textoTenue.g,
                               raiz.textoTenue.b, 0.45)
                font.pixelSize: 11
                font.letterSpacing: 3
                font.bold: true
            }

            // El foco al campo en cuanto aparece la pantalla: se empieza a
            // escribir sin buscar dónde pulsar. Va en Component.onCompleted y
            // no en un Keys.onPressed colgado de la superficie, porque
            // WlSessionLockSurface no es un Item y la propiedad Keys no se le
            // puede adjuntar ("Could not attach Keys property").
            Component.onCompleted: if (principal) entrada.forceActiveFocus()
            // Si resulta que no hay contraseña, el foco se mueve al bloque que
            // sí tiene salida por teclado.
            Connections {
                target: raiz
                function onSinClaveChanged() {
                    if (raiz.sinClave && superficie.principal) sinClaveCaja.forceActiveFocus()
                }
            }
        }
    }
}
