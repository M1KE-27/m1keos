import QtQuick

// Símbolo pequeño con un área pulsable decente alrededor. Un signo de ocho
// píxeles es imposible de acertar con el ratón por muy claro que se vea, así
// que el dibujo va pequeño pero la zona sensible mide 22x22.
Item {
    id: raiz
    property string texto: ""
    property color colorTexto: Paleta.texto
    property int tamano: 14
    property bool activable: true
    signal activado()

    width: 22
    height: 22

    Text {
        anchors.centerIn: parent
        text: raiz.texto
        color: raiz.colorTexto
        font.pixelSize: raiz.tamano
        font.bold: true
    }

    HoverHandler {
        enabled: raiz.activable
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        // 22x22 es poco para un dedo; el margen lo lleva a 38x38 reales.
        margin: 8
        enabled: raiz.activable
        onTapped: raiz.activado()
    }
}
