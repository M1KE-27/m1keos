import QtQuick
import QtQuick.Layouts

// Control numérico con menos / valor / más. Se repite en muchos ajustes, así
// que vive aparte en lugar de copiarse una fila de tres botones cada vez.
// El paso y los topes los pone quien lo use: el control no deja salirse.
Row {
    id: control
    property int valor: 0
    property int minimo: 0
    property int maximo: 100
    property int paso: 1
    property string sufijo: ""
    signal cambiado(int nuevo)

    spacing: 6
    Layout.alignment: Qt.AlignRight

    CtlButton {
        text: "−"
        small: true
        onClicked: if (control.valor - control.paso >= control.minimo)
                       control.cambiado(control.valor - control.paso)
    }
    Text {
        text: control.valor + control.sufijo
        color: Paleta.texto
        font.pixelSize: 11
        width: 40
        height: 22
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    CtlButton {
        text: "+"
        small: true
        onClicked: if (control.valor + control.paso <= control.maximo)
                       control.cambiado(control.valor + control.paso)
    }
}
