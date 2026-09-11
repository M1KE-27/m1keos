import QtQuick
import QtQuick.Layouts

// Editor de una zona de la barra: enseña sus módulos en orden y permite
// moverlos, quitarlos y añadir de los disponibles. Es el mismo componente
// para las tres zonas, que sólo se diferencian en su lista.
ColumnLayout {
    id: editor
    property string titulo: ""
    property string lista: ""
    property var raiz: null
    signal cambiada(string nueva)

    spacing: 6
    Layout.fillWidth: true

    Text {
        text: editor.titulo
        color: Paleta.texto
        font.pixelSize: 11
        font.bold: true
    }

    // Módulos colocados, en orden
    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: editor.raiz ? editor.raiz.listaDe(editor.lista) : []

            // El fondo va detrás y no alrededor: anclar la fila al centro de
            // un recuadro cuyo ancho depende de esa misma fila creaba un
            // bucle de dependencias que tumbaba el panel. Aquí el alto es
            // fijo y el ancho fluye en un solo sentido.
            Item {
                height: 26
                width: fila.width + 14

                Rectangle {
                    anchors.fill: parent
                    radius: 13
                    color: Paleta.superficie
                    border.width: 1
                    border.color: Paleta.borde
                }

                Row {
                    id: fila
                    x: 7
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Pulsable {
                        texto: "‹"
                        colorTexto: index > 0 ? Paleta.acento : Paleta.borde
                        activable: index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        onActivado: editor.cambiada(editor.raiz.moverEn(editor.lista, index, -1))
                    }

                    Text {
                        text: editor.raiz ? editor.raiz.nombreModulo(modelData) : modelData
                        color: Paleta.texto
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Pulsable {
                        texto: "›"
                        colorTexto: Paleta.acento
                        anchors.verticalCenter: parent.verticalCenter
                        onActivado: editor.cambiada(editor.raiz.moverEn(editor.lista, index, 1))
                    }

                    Pulsable {
                        texto: "✕"
                        colorTexto: Paleta.aviso
                        tamano: 12
                        anchors.verticalCenter: parent.verticalCenter
                        onActivado: editor.cambiada(editor.raiz.quitarDe(editor.lista, index))
                    }
                }
            }
        }

        Text {
            visible: !editor.lista || editor.lista.length === 0
            text: "vacía"
            color: Paleta.textoTenue
            font.pixelSize: 11
            font.italic: true
        }
    }
}
