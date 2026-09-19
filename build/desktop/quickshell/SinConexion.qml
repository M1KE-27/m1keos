import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Aviso de "esto necesita internet y ahora mismo no hay".
//
// Antes, el selector de fondos sin red se quedaba con la rejilla vacía y ya:
// ni un mensaje, ni una pista de qué pasaba, ni forma de saber si estaba
// cargando o roto. Una pantalla en blanco es la peor respuesta posible, porque
// obliga a adivinar.
//
// Dice además POR QUÉ no hay conexión, que es lo que decide qué hacer: no es
// lo mismo "no hay ninguna red conectada" que "hay internet pero falla el
// DNS". Eso lo averigua m-internet (ver build/mcore/m-internet).
//
// Uso:
//   SinConexion {
//       id: aviso
//       queHace: "Los fondos se descargan de Wallhaven."
//       onReintentado: recargar()
//   }
//   ...
//   aviso.comprobar()
Item {
    id: raiz

    // Una frase que explique para qué hacía falta la red aquí.
    property string queHace: ""
    // "ok" mientras no se sepa lo contrario: así no parpadea un error al abrir.
    property string estado: "ok"
    property string motivo: ""
    property bool comprobando: false
    readonly property bool hayInternet: estado === "ok"

    signal reintentado()

    visible: !hayInternet && !comprobando
    implicitHeight: visible ? contenido.implicitHeight + 40 : 0
    Layout.fillWidth: true

    function comprobar() {
        comprobando = true
        sonda.running = true
    }

    Process {
        id: sonda
        command: ["m-internet"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim().split("\t")
                raiz.estado = t[0] || "sin-salida"
                raiz.motivo = t.length > 1 ? t[1] : "No hay conexión a internet."
            }
        }
        onExited: raiz.comprobando = false
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 10
        color: Paleta.superficie
        border.color: Paleta.borde
        border.width: 1

        ColumnLayout {
            id: contenido
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 18
            spacing: 6

            RowLayout {
                spacing: 10
                Icono {
                    nombre: "sin-red"
                    tamano: 18
                    color: Paleta.aviso
                }
                Text {
                    text: Idioma.t("Sin conexión a internet")
                    color: Paleta.texto
                    font.pixelSize: 14
                    font.bold: true
                }
            }
            Text {
                text: raiz.motivo
                color: Paleta.textoTenue
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Text {
                visible: raiz.queHace !== ""
                text: raiz.queHace
                color: Paleta.textoTenue
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            CtlButton {
                text: Idioma.t("Reintentar")
                Layout.topMargin: 6
                onClicked: {
                    raiz.comprobar()
                    raiz.reintentado()
                }
            }
        }
    }
}
