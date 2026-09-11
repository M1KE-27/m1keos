import QtQuick
import QtQuick.Layouts

// Encabezado de grupo dentro del Centro de Control.
Text {
    property string texto: ""
    text: texto
    color: "#7d8794"
    font.pixelSize: 11
    font.bold: true
    Layout.fillWidth: true
}
