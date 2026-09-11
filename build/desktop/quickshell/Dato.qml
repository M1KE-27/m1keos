import QtQuick

// Valor informativo, sin control asociado.
Text {
    property string texto: ""
    text: texto
    color: Paleta.texto
    font.pixelSize: 11
    font.bold: true
}
