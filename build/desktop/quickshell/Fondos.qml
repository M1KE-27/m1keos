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
    property string acento: "#00d4ff"
    property color fondoPanel: "#14161d"
    property color bordePanel: "#252530"

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
        TapHandler { onTapped: ventanaFondos.abierto = false }
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
                    color: "#ffffff"; font.pixelSize: 17; font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 8
                    color: "#0e1017"
                    border.color: campo.activeFocus ? ventanaFondos.acento : ventanaFondos.bordePanel
                    border.width: 1

                    TextInput {
                        id: campo
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#e6e8ee"
                        font.pixelSize: 12
                        selectByMouse: true
                        selectionColor: ventanaFondos.acento
                        onAccepted: ventanaFondos.cargar(text.trim(), 1, false)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Buscar en Wallhaven: montañas, espacio, minimal..."
                            color: "#6a7080"
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

                    Repeater {
                        model: ventanaFondos.resultados

                        Rectangle {
                            id: tarjeta
                            width: 204
                            height: 128
                            radius: 10
                            color: "#0e1017"
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
                                cache: false
                                // Las miniaturas se descargan a un archivo
                                // temporal y sólo se renombran al terminar,
                                // así que un archivo con el nombre bueno
                                // está siempre completo. Mientras no exista,
                                // se reintenta.
                                onStatusChanged: if (status === Image.Error) reintento.start()
                            }

                            Timer {
                                id: reintento
                                interval: 400
                                repeat: true
                                property int vueltas: 0
                                onTriggered: {
                                    vueltas++
                                    // Un minuto largo de margen. Pasado eso
                                    // la miniatura no va a llegar y seguir
                                    // mirando el disco sólo gasta batería.
                                    if (vueltas > 150) { stop(); return }
                                    var s = miniatura.source
                                    miniatura.source = ""
                                    miniatura.source = s
                                    if (miniatura.status === Image.Ready) stop()
                                }
                            }

                            // Hueco mientras no hay imagen: la tarjeta existe
                            // desde el primer momento aunque su miniatura
                            // falle, en vez de desaparecer sin explicación.
                            Text {
                                anchors.centerIn: parent
                                text: "..."
                                color: "#3a4050"
                                font.pixelSize: 20
                                visible: miniatura.status !== Image.Ready
                            }

                            HoverHandler { id: raton }
                            TapHandler {
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

    Process {
        id: aplicar
        stdout: StdioCollector {
            onStreamFinished: ventanaFondos.estado =
                this.text.indexOf("[OK]") >= 0 ? "Fondo aplicado." : "No se pudo aplicar."
        }
    }
}
