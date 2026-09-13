import QtQuick

// Botón reutilizable del panel de control. Estático (no se regenera desde
// plantilla, a diferencia de shell.qml): m-apply-settings solo lo copia a
// la carpeta del usuario si falta.
Rectangle {
    id: btn
    property string text: ""
    property bool small: false
    property bool active: false
    signal clicked()

    // Ancho mínimo fijo: sin esto "US"/"Instant"/"Arriba" quedaban con
    // botones de tamaños dispares y la fila se veía desalineada.
    // Icono opcional a la izquierda del texto. Antes se colaba un carácter
    // suelto dentro del propio texto ("✎  Editar a mano"), que ni se alineaba
    // ni compartía grosor con los iconos de al lado.
    property string icono: ""

    implicitWidth: Math.max(contenido.implicitWidth + (small ? 18 : 24), small ? 48 : 62)
    implicitHeight: small ? 22 : 26
    // Cápsula completa, a juego con las islas redondeadas de la barra.
    radius: height / 2
    color: active ? Paleta.acento : (mouseArea.containsMouse ? Paleta.superficieAlta : Paleta.superficie)
    border.width: active ? 0 : 1
    border.color: Paleta.borde

    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: contenido
        anchors.centerIn: parent
        spacing: 6

        Icono {
            visible: btn.icono !== ""
            nombre: btn.icono
            tamano: btn.small ? 12 : 13
            color: btn.active ? Paleta.sobreAcento : Paleta.texto
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            id: label
            text: btn.text
            color: btn.active ? Paleta.sobreAcento : Paleta.texto
            font.pixelSize: btn.small ? 10 : 11
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Todo el panel derecho del Centro de Control vive dentro de un
        // Flickable. Sin esto, cualquier pulsación que se desplace unos
        // píxeles -- lo normal con un dedo en un touchpad -- se la queda el
        // Flickable como desplazamiento y el clic no llega nunca. Con un ratón
        // guionizado, que no se mueve ni un píxel, no pasaba jamás: de ahí que
        // funcionara en QEMU y no en un portátil de verdad.
        preventStealing: true
        onClicked: btn.clicked()
    }
}
