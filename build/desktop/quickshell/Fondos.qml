import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Selector de fondos de pantalla.
//
// Antes era una ventana GTK aparte (m-wallpapers) que descargaba las
// veinticuatro miniaturas con la interfaz congelada y no pintaba nada hasta
// tenerlas todas. Aquí las tarjetas salen en el acto y cada imagen entra
// cuando llega: Image de QML carga fuera del hilo de la interfaz por su
// cuenta, así que la ventana nunca se queda bloqueada.
//
// Sólo se descargan miniaturas. La imagen completa se baja únicamente al
// elegir un fondo, que es lo que se pide y lo que evita traer veinte
// imágenes de varios megabytes que nadie va a usar.
PanelWindow {
    id: ventanaFondos

    property bool abierto: false
    property string acento: Paleta.acento
    property color fondoPanel: Paleta.superficie
    property color bordePanel: Paleta.superficieAlta

    // Directorio de la caché. Persiste entre sesiones: volver a abrir el
    // selector con las mismas búsquedas no descarga nada.
    readonly property string cache: Quickshell.env("HOME") + "/.cache/mike/wallhaven-thumbs"

    property int pagina: 1
    property string consulta: ""
    property string estado: ""
    property var resultados: []

    visible: abierto
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    function abrir() {
        abierto = true
        // Se comprueba la red al abrir: si no hay, se dice, en vez de dejar
        // la rejilla en blanco y que cada uno adivine si carga o está rota.
        avisoRed.comprobar()
        if (resultados.length === 0) cargar("", 1, false)
    }

    // append=false sustituye la cuadrícula (búsqueda nueva); append=true
    // añade al final ("Ver más").
    function cargar(texto, pag, append) {
        consulta = texto
        pagina = pag
        estado = append ? "Cargando más..." : "Buscando..."
        listador.anexar = append
        listador.command = texto.length > 0
            ? ["m-wallhaven", "search", texto, String(pag)]
            : ["m-wallhaven", "toplist", String(pag)]
        listador.running = true
    }

    // Fondo oscurecido: separa la ventana del escritorio y se cierra al
    // pulsar fuera, como cualquier diálogo.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55
        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: ventanaFondos.abierto = false }
    }

    Rectangle {
        anchors.centerIn: parent
        width:  Math.min(parent.width  - 80, 1180)
        height: Math.min(parent.height - 80, 780)
        color: ventanaFondos.fondoPanel
        border.color: ventanaFondos.bordePanel
        border.width: 1
        radius: 18

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ---------- Cabecera ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Fondos de pantalla"
                    color: Paleta.texto; font.pixelSize: 17; font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 8
                    color: Paleta.fondo
                    border.color: campo.activeFocus ? ventanaFondos.acento : ventanaFondos.bordePanel
                    border.width: 1

                    TextInput {
                        id: campo
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: Paleta.texto
                        font.pixelSize: 12
                        selectByMouse: true
                        selectionColor: ventanaFondos.acento
                        onAccepted: ventanaFondos.cargar(text.trim(), 1, false)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Buscar en Wallhaven: montañas, espacio, minimal..."
                            color: Paleta.textoTenue
                            font.pixelSize: 12
                            visible: campo.text.length === 0 && !campo.activeFocus
                        }
                    }
                }

                CtlButton {
                    text: "Buscar"; small: true
                    onClicked: ventanaFondos.cargar(campo.text.trim(), 1, false)
                }
                CtlButton {
                    text: "Cerrar"; small: true
                    onClicked: ventanaFondos.abierto = false
                }
            }

            // ---------- Aviso de red ----------
            SinConexion {
                id: avisoRed
                queHace: "Los fondos se descargan de Wallhaven, que necesita internet. El de MIKE OS sí se puede poner sin red."
                onReintentado: ventanaFondos.cargar("", 1, false)
            }

            // ---------- Cuadrícula ----------
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: rejilla.height
                boundsBehavior: Flickable.StopAtBounds

                Grid {
                    id: rejilla
                    width: parent.width
                    columns: Math.max(1, Math.floor(width / 216))
                    spacing: 12

                    // El fondo de MIKE OS, siempre el primero.
                    //
                    // Faltaba: en cuanto aplicabas uno de Wallhaven no había
                    // forma de volver al de fábrica desde aquí. Y además es el
                    // único que se ve al instante, porque está en el disco y no
                    // depende de que la red traiga nada.
                    Rectangle {
                        width: 204
                        height: 128
                        radius: 10
                        color: Paleta.fondo
                        border.color: ratonPropio.hovered ? ventanaFondos.acento
                                                          : ventanaFondos.bordePanel
                        border.width: ratonPropio.hovered ? 2 : 1
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: "file:///usr/share/backgrounds/wallpaper.png"
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            gradient: Gradient {
                                GradientStop { position: 0.55; color: "transparent" }
                                GradientStop { position: 1.0;  color: "#cc000000" }
                            }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 10
                            text: "El de MIKE OS"
                            color: Paleta.texto
                            font.pixelSize: 12
                            font.bold: true
                        }

                        HoverHandler { id: ratonPropio }
                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: {
                                ventanaFondos.estado = "Aplicando fondo..."
                                volverAlPropio.running = true
                            }
                        }
                    }

                    Repeater {
                        model: ventanaFondos.resultados

                        Rectangle {
                            id: tarjeta
                            width: 204
                            height: 128
                            radius: 10
                            color: Paleta.fondo
                            border.color: raton.hovered ? ventanaFondos.acento : ventanaFondos.bordePanel
                            border.width: raton.hovered ? 2 : 1
                            clip: true

                            // asynchronous: la decodificación va fuera del
                            // hilo de la interfaz, así que una imagen grande
                            // no congela la ventana mientras se abre.
                            Image {
                                id: miniatura
                                anchors.fill: parent
                                anchors.margins: 1
                                source: "file://" + ventanaFondos.cache + "/" + modelData.id + ".jpg"
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // cache: true. Con la caché desactivada, cada
                                // reintento volvía a decodificar el JPEG desde
                                // el disco aunque ya estuviera pintado.
                                cache: true
                                // Las miniaturas se descargan a un archivo
                                // temporal y sólo se renombran al terminar, así
                                // que un archivo con el nombre bueno está
                                // siempre completo. Mientras no exista, se
                                // reintenta; en cuanto aparece, se para.
                                onStatusChanged: {
                                    if (status === Image.Error) reintento.start()
                                    else if (status === Image.Ready) reintento.stop()
                                }
                            }

                            Timer {
                                id: reintento
                                // 1,2 s en vez de 0,4: las miniaturas tardan lo
                                // que tarda la red, y mirar el disco tres veces
                                // por segundo no las trae antes.
                                interval: 1200
                                repeat: true
                                property int vueltas: 0
                                onTriggered: {
                                    vueltas++
                                    // Medio minuto. Pasado eso la miniatura no
                                    // va a llegar y seguir mirando el disco
                                    // sólo gasta batería.
                                    if (vueltas > 25) { stop(); return }
                                    // Si ya está pintada no se toca. Antes se
                                    // recargaba igualmente: la condición de
                                    // parada miraba el estado justo después de
                                    // asignar la ruta, y con carga asíncrona
                                    // en ese instante siempre es "Loading",
                                    // nunca "Ready". O sea que NUNCA paraba, y
                                    // seguía vaciando y recargando cada
                                    // miniatura durante un minuto: eso era el
                                    // parpadeo de toda la rejilla.
                                    if (miniatura.status === Image.Ready) { stop(); return }
                                    var s = miniatura.source
                                    miniatura.source = ""
                                    miniatura.source = s
                                }
                            }

                            // Hueco mientras no hay imagen: la tarjeta existe
                            // desde el primer momento aunque su miniatura
                            // falle, en vez de desaparecer sin explicación.
                            Text {
                                anchors.centerIn: parent
                                text: "..."
                                color: Paleta.borde
                                font.pixelSize: 20
                                visible: miniatura.status !== Image.Ready
                            }

                            HoverHandler { id: raton }
                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: {
                                    ventanaFondos.estado = "Aplicando fondo..."
                                    aplicar.command = ["m-wallhaven", "set", modelData.url]
                                    aplicar.running = true
                                }
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
                    text: ventanaFondos.estado
                    color: ventanaFondos.acento
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }
                CtlButton {
                    text: "Ver más"; small: true
                    onClicked: ventanaFondos.cargar(ventanaFondos.consulta,
                                                    ventanaFondos.pagina + 1, true)
                }
            }
        }
    }

    // ---------- Procesos ----------

    // m-wallhaven devuelve TSV: id, url-miniatura, url-completa.
    Process {
        id: listador
        property bool anexar: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lista = ventanaFondos.anexar_o_nuevo(listador.anexar)
                var urls = []
                for (const linea of this.text.trim().split("\n")) {
                    if (linea.length === 0) continue
                    const c = linea.split("\t")
                    if (c.length < 3) continue
                    lista.push({ id: c[0], miniatura: c[1], url: c[2] })
                    urls.push(c[1] + "\t" + ventanaFondos.cache + "/" + c[0] + ".jpg")
                }
                ventanaFondos.resultados = lista
                ventanaFondos.estado = lista.length + " fondos."
                if (urls.length > 0) {
                    descargador.command = ["m-wallhaven", "cache", urls.join("\n")]
                    descargador.running = true
                }
            }
        }
    }

    function anexar_o_nuevo(anexar) {
        return anexar ? resultados.slice() : []
    }

    // Descarga las miniaturas que falten, en segundo plano. La cuadrícula ya
    // está pintada para cuando esto arranca.
    Process { id: descargador }

    // m-fondo es quien pinta y recuerda el fondo (ver build/mcore/m-fondo):
    // así el de fábrica se guarda en los ajustes igual que cualquier otro y
    // sobrevive a cerrar la sesión.
    Process {
        id: volverAlPropio
        command: ["m-fondo", "poner", "/usr/share/backgrounds/wallpaper.png"]
        onExited: ventanaFondos.estado = exitCode === 0 ? "Fondo aplicado."
                                                        : "No se pudo aplicar."
    }

    Process {
        id: aplicar
        stdout: StdioCollector {
            onStreamFinished: ventanaFondos.estado =
                this.text.indexOf("[OK]") >= 0 ? "Fondo aplicado." : "No se pudo aplicar."
        }
    }
}
