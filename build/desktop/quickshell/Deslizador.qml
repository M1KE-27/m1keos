import QtQuick
import QtQuick.Layouts

// Deslizador de 0 a 100.
//
// Existe porque el control de volumen del Centro de Control eran dos botones
// "−" y "+" en los extremos opuestos de setecientos píxeles, con la palabra
// "Volumen" en medio y sin enseñar en ningún momento a qué volumen estabas.
// Un valor que va de 0 a 100 se regula arrastrando y se lee de un vistazo.
Item {
    id: control

    property int valor: 0
    property int minimo: 0
    property int maximo: 100
    property int paso: 5
    property string sufijo: "%"
    // Apagado: el mando se queda gris y no responde. Se usa cuando no hay
    // destino de audio, para no fingir un control que no controla nada.
    property bool activo: true
    signal cambiado(int nuevo)

    implicitHeight: 22
    Layout.fillWidth: true

    function desdeX(x) {
        var t = Math.max(0, Math.min(1, x / Math.max(1, barra.width)))
        var v = control.minimo + t * (control.maximo - control.minimo)
        // Se redondea al paso para que arrastrar no deje valores como 37.
        return Math.round(v / control.paso) * control.paso
    }

    Rectangle {
        id: barra
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: lectura.left
        anchors.rightMargin: 12
        height: 4
        radius: 2
        color: Paleta.borde

        Rectangle {
            width: parent.width * (control.valor - control.minimo)
                   / Math.max(1, control.maximo - control.minimo)
            height: parent.height
            radius: parent.radius
            color: control.activo ? Paleta.acento : Paleta.textoTenue
            Behavior on width { NumberAnimation { duration: 90 } }
        }

        Rectangle {
            id: mando
            width: 13; height: 13; radius: 7
            y: (parent.height - height) / 2
            x: parent.width * (control.valor - control.minimo)
               / Math.max(1, control.maximo - control.minimo) - width / 2
            color: control.activo ? Paleta.acento : Paleta.textoTenue
            border.width: 2
            border.color: Paleta.superficie
            scale: raton.pressed ? 1.25 : (raton.containsMouse ? 1.12 : 1)
            Behavior on x { NumberAnimation { duration: 90 } }
            Behavior on scale { NumberAnimation { duration: 110 } }
        }

        MouseArea {
            id: raton
            // Alto generoso: la barra mide 4 px, pero acertarle con el ratón
            // no debe ser puntería.
            anchors.fill: parent
            anchors.topMargin: -9
            anchors.bottomMargin: -9
            enabled: control.activo
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (e) => control.cambiado(control.desdeX(e.x))
            onPositionChanged: (e) => { if (pressed) control.cambiado(control.desdeX(e.x)) }
            onWheel: (e) => {
                var v = control.valor + (e.angleDelta.y > 0 ? control.paso : -control.paso)
                control.cambiado(Math.max(control.minimo, Math.min(control.maximo, v)))
            }
        }
    }

    Text {
        id: lectura
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 42
        horizontalAlignment: Text.AlignRight
        text: control.activo ? control.valor + control.sufijo : "—"
        color: control.activo ? Paleta.texto : Paleta.textoTenue
        font.pixelSize: 11
        font.bold: true
    }
}
