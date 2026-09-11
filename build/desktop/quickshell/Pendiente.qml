import QtQuick
import QtQuick.Layouts

// Aviso honesto para un apartado todavía sin función: es preferible decir
// que falta a enseñar interruptores que no hacen nada.
Text {
    property string texto: ""
    text: "— " + texto
    color: "#55606f"
    font.pixelSize: 11
    font.italic: true
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
}
