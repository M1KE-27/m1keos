import QtQuick
import QtQuick.Layouts

// Encabezado de grupo dentro del Centro de Control.
Text {
    property string texto: ""
    text: texto
    color: Paleta.textoTenue
    font.pixelSize: 11
    font.bold: true
    Layout.fillWidth: true
}
