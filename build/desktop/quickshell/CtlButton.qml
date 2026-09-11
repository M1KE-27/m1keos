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
    implicitWidth: Math.max(label.implicitWidth + (small ? 18 : 24), small ? 48 : 62)
    implicitHeight: small ? 22 : 26
    // Cápsula completa, a juego con las islas redondeadas de la barra.
    radius: height / 2
    color: active ? "#00d4ff" : (mouseArea.containsMouse ? "#252b38" : "#1a1f2b")
    border.width: active ? 0 : 1
    border.color: "#2b3243"

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        color: btn.active ? "#000000" : "#c9c9d4"
        font.pixelSize: btn.small ? 10 : 11
        font.bold: true
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
