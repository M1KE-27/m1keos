pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// En qué idioma habla el escritorio.
//
// Por qué existe
// --------------
// El instalador lleva desde el primer día preguntando "Choose your language",
// ofreciendo English y Español, y prometiendo debajo que se puede cambiar
// luego "in the Control Centre". Ninguna de las dos cosas era verdad: la
// elección sólo se usaba para los avisos de m-particiones durante la propia
// instalación, no se guardaba en ninguna parte, y en el Centro de Control no
// había dónde cambiarla. Elegías English, instalabas, arrancabas, y tenías un
// sistema entero en español.
//
// Por qué un singleton y no una propiedad de shell.qml
// ---------------------------------------------------
// Porque la pantalla de bloqueo (bloqueo.qml) es OTRO programa: Quickshell la
// carga aparte, así que no ve las propiedades de la barra. Con el diccionario
// en shell.qml, el Centro de Control se traducía y el bloqueo --- que es
// justo la pantalla que ve alguien que no ha entrado todavía --- se quedaba
// en español.
//
// Por qué sin gettext
// -------------------
// Son dos idiomas. Un catálogo binario, su compilador y un /usr/share/locale
// es más infraestructura de la que paga hoy. La clave del diccionario es el
// texto en español --- el que ya estaba escrito --- y no un identificador, así
// que esto se lee como una lista de equivalencias en vez de obligar a saltar a
// otro archivo para saber qué dice cada cadena.
//
// Lo que falte sale en español. Es feo, pero un hueco vacío o un identificador
// crudo en mitad de la pantalla es peor. tests/traducciones.sh está para que
// eso no llegue a una imagen.
Singleton {
    id: idioma

    // "es" o "en". Es una propiedad y no una constante: todo lo que se pinta
    // pasa por T(), que la lee, así que cambiarla vuelve a evaluar cada enlace
    // y la ventana entera cambia de idioma sin cerrarse ni reiniciar sesión.
    property string actual: "es"

    readonly property var traducciones: ({
        "Vistazo":
            "At a glance",
        "Sistema":
            "System",
        "Energía":
            "Power",
        "Controladores":
            "Drivers",
        "Barra":
            "Bar",
        "Escritorio":
            "Desktop",
        "Bloqueo":
            "Lock screen",
        "Acerca de":
            "About",
        "Centro de Control":
            "Control Centre",
        "Cerrar":
            "Close",
        "Editar a mano":
            "Edit by hand",
        "Los cambios se guardan solos":
            "Changes are saved automatically",
        "Sonido":
            "Sound",
        "No hay ninguna salida de audio conectada.":
            "No audio output is connected.",
        "Red":
            "Network",
        "Buscar":
            "Scan",
        "Redes inalámbricas: no se detecta adaptador.":
            "Wireless networks: no adapter detected.",
        "Bluetooth":
            "Bluetooth",
        "No se detecta adaptador Bluetooth.":
            "No Bluetooth adapter detected.",
        "Fondo de pantalla":
            "Wallpaper",
        "Elegir fondo...":
            "Choose a wallpaper…",
        "Teclado":
            "Keyboard",
        "Distribución":
            "Layout",
        "Hora":
            "Time",
        "Formato":
            "Format",
        "24 h":
            "24 h",
        "12 h am":
            "12 h am",
        "12 h AM":
            "12 h AM",
        "Mostrar segundos":
            "Show seconds",
        "Sí":
            "Yes",
        "No":
            "No",
        "Idioma":
            "Language",
        "El sistema entero: esta ventana, la barra y la bienvenida.":
            "The whole system: this window, the bar and the welcome screen.",
        "Sonido y batería llegan en el Bloque 2.":
            "Sound and battery are coming in Block 2.",
        "Perfil":
            "Profile",
        "Modo":
            "Mode",
        "Automático":
            "Automatic",
        "Ahorro":
            "Battery saver",
        "Equilibrado":
            "Balanced",
        "Máximo":
            "Maximum",
        "Estado":
            "Status",
        "Actualizar":
            "Refresh",
        "Pulsa «Actualizar» para leerlo.":
            "Press “Refresh” to read it.",
        "Al cerrar la tapa":
            "When the lid closes",
        "Hacer":
            "Do",
        "Apagar pantalla":
            "Turn the screen off",
        "Suspender":
            "Suspend",
        "Hibernar":
            "Hibernate",
        "Nada":
            "Nothing",
        "La sesión se bloquea siempre al cerrar, hagas lo que hagas con el resto. ":
            "The session always locks when the lid closes, whatever you pick here. ",
        "Suspender ahora":
            "Suspend now",
        "Hibernar ahora":
            "Hibernate now",
        "Este equipo":
            "This machine",
        "Analizando…":
            "Scanning…",
        "Analizar de nuevo":
            "Scan again",
        "Informe completo":
            "Full report",
        "Último análisis: ":
            "Last scan: ",
        "Todavía no se ha analizado nada.":
            "Nothing has been scanned yet.",
        "el análisis falló":
            "the scan failed",
        "Recomendado para este equipo":
            "Recommended for this machine",
        "Instalar lo recomendado":
            "Install what is recommended",
        "No falta nada: el sistema ya cubre este equipo.":
            "Nothing is missing: the system already covers this machine.",
        "funciona":
            "working",
        "Posición":
            "Position",
        "Lado de la pantalla":
            "Side of the screen",
        "Arriba":
            "Top",
        "Abajo":
            "Bottom",
        "Izquierda":
            "Left",
        "Derecha":
            "Right",
        "Forma":
            "Shape",
        "Pegada":
            "Attached",
        "Isla":
            "Island",
        "Completa":
            "Full width",
        "Agrupación":
            "Grouping",
        "Islas":
            "Islands",
        "Continua":
            "Continuous",
        "Bordes de pantalla":
            "Screen corners",
        "Redondeados":
            "Rounded",
        "Rectos":
            "Square",
        "Tamaños":
            "Sizes",
        "Alto de la barra":
            "Bar height",
        "Alto de los módulos":
            "Module height",
        "Tamaño de letra":
            "Font size",
        "Separación":
            "Spacing",
        "Opacidad":
            "Opacity",
        "Ocultar sola":
            "Hide by itself",
        "Módulos de la barra":
            "Bar modules",
        "‹ y › mueven dentro de la zona; ✕ quita de la barra.":
            "‹ and › move within the zone; ✕ removes it from the bar.",
        "Centro":
            "Centre",
        "Colocar un módulo":
            "Add a module",
        "Izq":
            "L",
        "Der":
            "R",
        "Identidad":
            "Identity",
        "Espacios":
            "Workspaces",
        "Reloj":
            "Clock",
        "Batería":
            "Battery",
        "Medidores":
            "Meters",
        "Volumen":
            "Volume",
        "Botones":
            "Buttons",
        "Ajustes":
            "Settings",
        "Espacios y efectos":
            "Workspaces and effects",
        "Espacios de trabajo":
            "Workspaces",
        "Desenfoque":
            "Blur",
        "Opacidad de la terminal":
            "Terminal opacity",
        "Animaciones":
            "Animations",
        "Sin":
            "None",
        "Rápidas":
            "Fast",
        "Suaves":
            "Smooth",
        "Color de acento":
            "Accent colour",
        "Interfaz":
            "Interface",
        "Avisos, vista general y tipografías llegan en el Bloque 4. La pantalla de bloqueo tiene apartado propio.":
            "Notifications, overview and fonts are coming in Block 4. The lock screen has its own section.",
        "Pantalla de bloqueo":
            "Lock screen",
        "Contraseña de la cuenta":
            "Account password",
        "puesta":
            "set",
        "Puesta":
            "Set",
        "Cambiar":
            "Change",
        "Poner":
            "Set one",
        "Bloquear ahora":
            "Lock now",
        "Bloquear":
            "Lock",
        "Reiniciar el equipo":
            "Restart the machine",
        "Reiniciar":
            "Restart",
        "Apagar el equipo":
            "Shut the machine down",
        "Apagar":
            "Shut down",
        "Esta cuenta no tiene contraseña, así que el bloqueo deja entrar sin preguntar. Ponle una aquí arriba.":
            "This account has no password, so the lock screen lets anyone straight in. Set one above.",
        "La contraseña está cifrada con DES, que sólo mira sus 8 primeros caracteres. Vuelve a ponerla desde aquí para pasarla a sha512.":
            "The password is hashed with DES, which only looks at its first 8 characters. Set it again from here to move it to sha512.",
        "Aviso: con la cuenta en el grupo «wheel», m-sudo da root sin pedir contraseña. El bloqueo protege de miradas, no de alguien con tiempo y teclado.":
            "Note: with the account in the “wheel” group, m-sudo gives root without asking for a password. The lock screen protects against onlookers, not against someone with time and a keyboard.",
        "El bloqueo automático por inactividad todavía no está: Quickshell 0.3.1 no expone el aviso de inactividad de Wayland. De momento se bloquea a mano con SUPER+L.":
            "Automatic locking on idle is not there yet: Quickshell 0.3.1 does not expose Wayland's idle notification. For now, lock by hand with SUPER+L.",
        "Servicios":
            "Services",
        "Frecuencia de medición, carpetas de destino y buscador llegan en el Bloque 5.":
            "Sampling rate, destination folders and the search tool are coming in Block 5.",
        "Avanzado":
            "Advanced",
        "Aplicar la paleta a la shell, a las aplicaciones Qt y a la terminal llega en el Bloque 6.":
            "Applying the palette to the shell, to Qt applications and to the terminal is coming in Block 6.",
        "Versión ":
            "Version ",
        "Arranque":
            "Init",
        "Paquetes":
            "Packages",
        "Compositor":
            "Compositor",
        "Intérprete":
            "Shell",
        "Se apoya en":
            "Built on",
        "sin red":
            "no network",
        "sin audio":
            "no audio",
        "mudo":
            "muted",
        "desconocida":
            "unknown",
        "Pulsa Intro para cerrar.":
            "Press Enter to close.",

        "Desbloquear":
            "Unlock",
        "Contraseña":
            "Password",
        "Esta cuenta no tiene contraseña, así que no hay nada que comprobar.":
            "This account has no password, so there is nothing to check.",
        "Pulsa Intro para abrir. Ponle una contraseña con «m-clave poner» y el bloqueo empezará a servir de algo.":
            "Press Enter to open. Set a password with “m-clave poner” and the lock screen will start being worth something.",
        "Bloq Mayús está activado":
            "Caps Lock is on",
        "Teclado: ":
            "Keyboard: ",
        "Sin conexión a internet":
            "No internet connection",
        "Reintentar":
            "Try again",
        "Fondos de pantalla":
            "Wallpapers",
        "Buscar en Wallhaven: montañas, espacio, minimal...":
            "Search Wallhaven: mountains, space, minimal…",
        "El de MIKE OS":
            "The MIKE OS one",
        "Ver más":
            "See more",
        "vacía":
            "empty",

        "sin driver":
            "no driver",
        "falta firmware":
            "firmware missing",
        "parado":
            "stopped",
        "no hay":
            "none",

        // No se traducen: son nombres propios, siglas o marcas. Están en la
        // lista para que la prueba distinga "decidido que se queda igual" de
        // "se olvidó traducirlo".
        " · x86_64":
            " · x86_64",
        "ES":
            "ES",
        "US":
            "US",
        "Hyprland":
            "Hyprland",
        "Hyprland · Quickshell · BusyBox · runit · Mesa":
            "Hyprland · Quickshell · BusyBox · runit · Mesa",
        "MIKE":
            "MIKE",
        "MIKE OS":
            "MIKE OS",
        "MIKE OS ":
            "MIKE OS ",
        "OS":
            "OS",
        "bash":
            "bash",
        "mpm":
            "mpm",
        "runit":
            "runit"
    })

    // En minúscula y no "T": QML reserva las mayúsculas iniciales para los
    // nombres de tipo, y un método que empieza por mayúscula no es un aviso
    // sino un error de carga --- "Method names cannot begin with an upper case
    // letter". Y como este archivo es un singleton declarado en qmldir, el
    // error no se queda en él: invalida el módulo entero, así que TODOS los
    // componentes de la carpeta dejan de existir y el escritorio no arranca.
    function t(es: string): string {
        if (idioma.actual !== "en") return es
        var v = idioma.traducciones[es]
        return v !== undefined ? v : es
    }

    // Quién manda: m-idioma, que mira $MIKEOS_LANG antes que /etc/mikeos/idioma
    // --- así se puede sacar una captura en inglés sin tocar la configuración
    // del equipo, que es como se hacen las de la web inglesa.
    Process {
        id: leer
        running: true
        command: ["m-idioma"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = text.trim()
                if (v === "es" || v === "en") idioma.actual = v
            }
        }
    }

    // Escribir en /etc necesita root, y por eso pasa por m-idioma, que vuelve
    // a entrar por m-sudo. La propiedad se mueve sin esperar a que termine: si
    // la escritura fallara, la siguiente lectura la devuelve a su sitio.
    Process { id: poner; command: ["m-idioma", "es"] }

    function cambiar(cual: string): void {
        if (cual !== "es" && cual !== "en") return
        idioma.actual = cual
        poner.command = ["m-idioma", cual]
        poner.running = true
    }

    // Para que la pantalla de bloqueo y la barra se enteren de un cambio hecho
    // desde el Centro de Control: son procesos distintos y no comparten la
    // propiedad, sólo el archivo.
    property var vigilante: FileView {
        path: "/etc/mikeos/idioma"
        watchChanges: true
        onFileChanged: leer.running = true
    }
}
