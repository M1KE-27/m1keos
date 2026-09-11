import QtQuick
import QtQuick.Layouts

// Nombre de un ajuste, columna izquierda de las rejillas.
Text {
    property string texto: ""
    text: texto
    color: "#c9d1dc"
    font.pixelSize: 11
    Layout.preferredWidth: 150
}
