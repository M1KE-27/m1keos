pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Paleta única de MIKE OS.
//
// Antes cada archivo llevaba sus propios colores a mano: dieciocho valores
// distintos repartidos por la barra, el Centro de Control y los componentes,
// y el acento cian metido a fuego en sitios que no lo leían del ajuste. El
// resultado era que todo iba resaltado con el mismo color -- títulos, iconos,
// bordes, logo -- y cuando todo resalta, no resalta nada.
//
// Regla: cinco colores para construir, y el acento SÓLO para lo que está
// activo ahora mismo. Nada más lo usa.
QtObject {
    id: paleta

    // --- Los cinco ---
    readonly property color fondo:      "#0b0d11"  // el lienzo
    readonly property color superficie: "#161a21"  // cápsulas y ventanas
    readonly property color borde:      "#262c36"  // separaciones
    readonly property color texto:      "#e8ebf0"  // lo que se lee
    readonly property color textoTenue: "#79818f"  // lo secundario

    // --- Derivados, para no inventar tonos sueltos por ahí ---
    readonly property color superficieAlta: "#1f242d"  // bajo el cursor
    readonly property color sobreAcento:    "#05070c"  // texto encima del acento
    readonly property color aviso:          "#e3a13c"  // un valor que se pasa de la raya
    readonly property color ok:             "#4cc38a"  // algo que va bien

    // --- El acento, y sólo para lo activo ---
    // Lo lee del mismo settings.json que la barra, así que cambiarlo en el
    // Centro de Control lo cambia en todas partes a la vez, botones incluidos.
    // Antes CtlButton llevaba "#00d4ff" escrito dentro y se quedaba en cian
    // aunque eligieras otro color.
    property color acento: "#00d4ff"

    property var vigilante: FileView {
        path: Quickshell.env("HOME") + "/.config/mike/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var a = JSON.parse(text())
                if (a && a.accent_color) paleta.acento = a.accent_color
            } catch (e) {
                // Un archivo a medio escribir no debe dejar el sistema sin color.
            }
        }
    }

    // Acento rebajado, para fondos de "esto está seleccionado" sin gritar.
    function tenue(alfa) {
        return Qt.rgba(paleta.acento.r, paleta.acento.g, paleta.acento.b, alfa)
    }
}
