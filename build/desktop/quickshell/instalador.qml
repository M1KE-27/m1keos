//==============================================================================
// instalador.qml - El instalador de MIKE OS.
//==============================================================================
//
// Hasta ahora, instalar MIKE OS consistía en saber que existía una orden
// llamada "m-install" y escribirla en una terminal. Quien probaba el USB no
// tenía forma de descubrirlo, y quien lo descubría se encontraba con preguntas
// sobre subvolúmenes de btrfs. Esto es lo contrario: seis pantallas, todo
// propuesto de antemano, y nada que haya que saber para llegar al final.
//
// Lo que NO hace este archivo: particionar, formatear ni copiar. Todo eso lo
// sigue haciendo m-install, que es código probado y que borra discos. Aquí se
// recogen las respuestas y se le llaman con ellas (m-install --si). Una sola
// implementación de la parte peligrosa, y una interfaz que la conduce.
//
// El orden de las pantallas no es casual:
//
//   1. Idioma      en inglés por defecto, porque es lo que espera alguien que
//                  se descarga una ISO sin saber de dónde viene.
//   2. Internet    ANTES que nada, porque lo que se pueda hacer después
//                  depende de si la hay. Se puede seguir sin ella; lo que
//                  entonces no se puede hacer aparece atenuado y dice por qué,
//                  en vez de fallar a mitad de la instalación.
//   3. Disco       detectado solo, con aviso claro si es extraíble.
//   4. Cuenta      nombre del equipo y contraseña.
//   5. Aspecto     el fondo, elegido antes de instalar, para que el sistema
//                  sea suyo desde el primer arranque y no un escritorio ajeno.
//   6. Resumen     lo último que se ve antes de que algo sea irreversible.
//
// Lo lanza m-instalador.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: raiz

    // ------------------------------------------------------------------
    // Idioma
    // ------------------------------------------------------------------
    // Dos diccionarios y una función. Sin librerías de traducción: son dos
    // idiomas y meter gettext aquí sería más infraestructura que texto.
    property string idioma: "en"

    readonly property var textos: ({
        "en": {
            titulo: "Install MIKE OS",
            siguiente: "Next", atras: "Back", cancelar: "Cancel",
            paso: "Step",

            idiomaTitulo: "Choose your language",
            idiomaPie: "You can change this later in the Control Centre.",

            redTitulo: "Connect to the internet",
            redTexto: "MIKE OS installs perfectly well without a connection. " +
                      "With one, it can also fetch drivers for your hardware and " +
                      "check for updates while it installs.",
            redBuscar: "Scan for networks",
            redBuscando: "Scanning…",
            redSinAdaptador: "No Wi-Fi adapter found. Plug in a cable, or carry on without a connection.",
            redConectada: "Connected",
            redSinConexion: "Not connected",
            redSaltar: "Continue without internet",
            redContrasena: "Wi-Fi password",
            redConectar: "Connect",
            redConectando: "Connecting…",
            redFallo: "Could not connect. Check the password and try again.",

            sshTitulo: "Let someone help you remotely",
            sshTexto: "Turns on SSH so a friend can connect from their own computer " +
                      "and give you a hand with the install.",
            sshActivar: "Turn on remote help",
            sshCerrar: "Turn it off",
            sshAbierto: "Remote help is ON",
            sshComo: "On their computer, they type:",
            sshClaveEs: "and the password:",
            sshAviso: "Only while you are installing. Once MIKE OS is installed, SSH keeps working " +
                      "but asks for the password you choose on the next screen.",
            sshPorQueClave: "This is a throwaway account, made just now and deleted when you turn " +
                            "this off. It has a password because SSH here refuses blank ones, and " +
                            "because on a shared network anyone could otherwise walk in.",
            sshSinRed: "Needs a network connection first.",

            discoTitulo: "Where should MIKE OS go?",
            discoTexto: "Everything on the chosen disk will be erased.",
            discoNinguno: "No disk available. The one you booted from is never offered.",
            discoExtraible: "This is a removable drive.",
            discoFs: "Filesystem",
            discoBtrfs: "btrfs — snapshots before every update, full rollback",
            modoTitulo: "How should it be installed?",
            modoBorrar: "Erase the disk and start clean",
            modoBorrarSub: "Everything on it goes. Simplest, and what you want on a new disk.",
            modoLado: "Install alongside what is already there",
            modoLadoSub: "Uses only free space. Nothing else on the disk is touched.",
            modoReemplazar: "Replace one partition",
            modoReemplazarSub: "Only that partition is erased.",
            modoLibre: "free",
            avanzado: "Advanced partitioning",
            avanzadoSub: "Resize, create or delete partitions with GParted.",
            avanzadoInstalar: "Get GParted",
            avanzadoBajando: "Downloading…",
            avanzadoAbrir: "Open GParted",
            avanzadoRed: "Needs an internet connection",
            revisarTitulo: "This will not work yet",
            revisarVolver: "Back to the disk",
            revisando: "Checking…",
            discoExt4: "ext4 — simpler, no snapshots",

            cuentaTitulo: "Your account",
            cuentaEquipo: "Computer name",
            cuentaClave: "Password",
            cuentaRepetir: "Repeat password",
            cuentaSinClave: "Leave empty for no password",
            cuentaNoCoincide: "The passwords do not match.",
            cuentaAvisoVacia: "Without a password, the lock screen lets anyone straight in.",

            aspectoTitulo: "Make it yours",
            aspectoTexto: "Pick a background now, so the system looks like yours from the first boot.",
            aspectoDefecto: "MIKE OS default",
            aspectoPropio: "Choose a file…",
            aspectoColores: "Take the whole system's colours from this background",
            aspectoColoresTexto: "Bar, Control Centre, terminal and window borders.",
            aspectoMasFondos: "More backgrounds online",
            aspectoNecesitaRed: "Needs an internet connection",

            resumenTitulo: "Ready to install",
            resumenDisco: "Disk", resumenFs: "Filesystem",
            resumenEquipo: "Computer name", resumenClave: "Password",
            resumenTeclado: "Keyboard", resumenZona: "Time zone",
            resumenFondo: "Background", resumenRed: "Internet",
            resumenSi: "set", resumenNo: "none",
            resumenInstalar: "Install now",
            resumenAviso: "This erases everything on the disk above. There is no undo.",

            instalandoTitulo: "Installing MIKE OS",
            instalandoTexto: "This takes a couple of minutes. You can watch what it is doing below.",

            listoTitulo: "MIKE OS is installed",
            listoTexto: "Remove the USB stick and restart.",
            listoReiniciar: "Restart now",
            listoCerrar: "Close",

            falloTitulo: "The installation did not finish",
            falloTexto: "Nothing else will be written. The details are below; " +
                        "your disk may be partly written to."
        },
        "es": {
            titulo: "Instalar MIKE OS",
            siguiente: "Siguiente", atras: "Atrás", cancelar: "Cancelar",
            paso: "Paso",

            idiomaTitulo: "Elige tu idioma",
            idiomaPie: "Puedes cambiarlo luego en el Centro de Control.",

            redTitulo: "Conéctate a internet",
            redTexto: "MIKE OS se instala perfectamente sin conexión. Con ella, " +
                      "además puede traer los controladores de tu equipo y mirar " +
                      "si hay actualizaciones mientras instala.",
            redBuscar: "Buscar redes",
            redBuscando: "Buscando…",
            redSinAdaptador: "No hay adaptador WiFi. Conecta un cable o sigue sin conexión.",
            redConectada: "Conectado",
            redSinConexion: "Sin conexión",
            redSaltar: "Seguir sin internet",
            redContrasena: "Contraseña del WiFi",
            redConectar: "Conectar",
            redConectando: "Conectando…",
            redFallo: "No se ha podido conectar. Revisa la contraseña e inténtalo otra vez.",

            sshTitulo: "Que alguien te ayude desde fuera",
            sshTexto: "Enciende SSH para que alguien de confianza pueda entrar desde su " +
                      "ordenador y echarte una mano con la instalación.",
            sshActivar: "Activar ayuda remota",
            sshCerrar: "Desactivar",
            sshAbierto: "Ayuda remota ACTIVADA",
            sshComo: "En su ordenador, que escriba:",
            sshClaveEs: "y la contraseña:",
            sshAviso: "Sólo mientras instalas. Cuando MIKE OS esté instalado, SSH sigue " +
                      "funcionando pero pide la contraseña que elijas en la pantalla siguiente.",
            sshPorQueClave: "Es una cuenta de usar y tirar, creada ahora mismo y borrada al " +
                            "desactivar esto. Lleva contraseña porque el SSH de este sistema " +
                            "rechaza las vacías, y porque en una red compartida cualquiera " +
                            "podría entrar si no la hubiera.",
            sshSinRed: "Antes hace falta conexión de red.",

            discoTitulo: "¿Dónde va MIKE OS?",
            discoTexto: "Se borrará todo lo que haya en el disco elegido.",
            discoNinguno: "No hay ningún disco disponible. El medio del que has arrancado nunca se ofrece.",
            discoExtraible: "Es una unidad extraíble.",
            discoFs: "Sistema de archivos",
            discoBtrfs: "btrfs — instantáneas antes de cada actualización, rollback completo",
            modoTitulo: "¿Cómo lo instalamos?",
            modoBorrar: "Borrar el disco y empezar de cero",
            modoBorrarSub: "Se va todo lo que tenga. Lo más sencillo, y lo que quieres en un disco nuevo.",
            modoLado: "Instalar al lado de lo que ya hay",
            modoLadoSub: "Usa sólo el espacio libre. No se toca nada más del disco.",
            modoReemplazar: "Reemplazar una partición",
            modoReemplazarSub: "Sólo se borra esa partición.",
            modoLibre: "libres",
            avanzado: "Particionado avanzado",
            avanzadoSub: "Redimensionar, crear o borrar particiones con GParted.",
            avanzadoInstalar: "Traer GParted",
            avanzadoBajando: "Descargando…",
            avanzadoAbrir: "Abrir GParted",
            avanzadoRed: "Necesita conexión a internet",
            revisarTitulo: "Así todavía no va a funcionar",
            revisarVolver: "Volver al disco",
            revisando: "Comprobando…",
            discoExt4: "ext4 — más simple, sin instantáneas",

            cuentaTitulo: "Tu cuenta",
            cuentaEquipo: "Nombre del equipo",
            cuentaClave: "Contraseña",
            cuentaRepetir: "Repite la contraseña",
            cuentaSinClave: "Déjala vacía para no poner ninguna",
            cuentaNoCoincide: "Las contraseñas no coinciden.",
            cuentaAvisoVacia: "Sin contraseña, la pantalla de bloqueo deja entrar sin preguntar.",

            aspectoTitulo: "Hazlo tuyo",
            aspectoTexto: "Elige el fondo ahora, y el sistema será tuyo desde el primer arranque.",
            aspectoDefecto: "El de MIKE OS",
            aspectoPropio: "Elegir un archivo…",
            aspectoColores: "Sacar los colores de TODO el sistema de este fondo",
            aspectoColoresTexto: "Barra, Centro de Control, terminal y bordes de ventana.",
            aspectoMasFondos: "Más fondos de internet",
            aspectoNecesitaRed: "Necesita conexión a internet",

            resumenTitulo: "Todo listo",
            resumenDisco: "Disco", resumenFs: "Sistema de archivos",
            resumenEquipo: "Nombre del equipo", resumenClave: "Contraseña",
            resumenTeclado: "Teclado", resumenZona: "Zona horaria",
            resumenFondo: "Fondo", resumenRed: "Internet",
            resumenSi: "puesta", resumenNo: "sin poner",
            resumenInstalar: "Instalar ahora",
            resumenAviso: "Esto borra todo lo que haya en el disco de arriba. No hay vuelta atrás.",

            instalandoTitulo: "Instalando MIKE OS",
            instalandoTexto: "Tarda un par de minutos. Abajo puedes ver lo que va haciendo.",

            listoTitulo: "MIKE OS está instalado",
            listoTexto: "Saca el USB y reinicia.",
            listoReiniciar: "Reiniciar ahora",
            listoCerrar: "Cerrar",

            falloTitulo: "La instalación no ha terminado",
            falloTexto: "No se va a escribir nada más. Abajo están los detalles; " +
                        "puede que el disco se haya quedado a medias."
        }
    })

    function t(clave) {
        var d = textos[idioma]
        return (d && d[clave] !== undefined) ? d[clave] : clave
    }

    // ------------------------------------------------------------------
    // Estado
    // ------------------------------------------------------------------
    readonly property var pasos: ["idioma", "red", "disco", "cuenta",
                                  "aspecto", "resumen", "instalando", "listo"]
    property int paso: 0
    readonly property string pasoActual: pasos[paso]

    // Red
    property bool hayInternet: false
    property bool buscandoRed: false
    property bool conectandoRed: false
    property string errorRed: ""
    property var redes: []
    property string redElegida: ""
    property string claveRed: ""
    property bool sinAdaptador: false

    // Ayuda remota por SSH
    property bool sshAbierto: false
    property string sshIp: ""
    property string sshUsuario: "mike"
    property string sshClave: ""
    property string sshError: ""

    // Disco
    property var discos: []
    property int discoIdx: -1
    property string fs: "btrfs"
    // borrar | al-lado | reemplazar
    property string modo: "borrar"
    property string particionObjetivo: ""
    property var particiones: []
    property double espacioLibre: 0
    property bool gpartedPuesto: false
    property bool bajandoGparted: false
    // Lo que ha dicho la comprobación previa.
    property var problemas: []
    property var avisos: []
    property bool comprobandoDisco: false
    readonly property var discoSel: (discoIdx >= 0 && discoIdx < discos.length)
                                    ? discos[discoIdx] : null

    // Cuenta
    property string equipo: "mikeos"
    property string clave: ""
    property string clave2: ""

    // Aspecto
    property string fondoElegido: ""      // vacío = el de fábrica
    property bool coloresDelFondo: false

    // Instalación
    property string registro: ""
    property bool instalando: false
    property bool termino: false
    property bool fallo: false

    readonly property color acento: Paleta.acento
    readonly property color fondoBase: Paleta.fondo

    function siguiente() { if (paso < pasos.length - 1) paso++ }
    function atras()     { if (paso > 0) paso-- }

    // ¿Se puede avanzar desde donde estamos?
    function puedeSeguir() {
        switch (pasoActual) {
        case "disco":  return discoSel !== null && problemas.length === 0
                              && !comprobandoDisco
        case "cuenta": return clave === clave2
        case "resumen": return problemas.length === 0
        default:       return true
        }
    }

    function bytesLegibles(b) {
        var n = Number(b)
        if (!(n > 0)) return "?"
        if (n >= 1e12) return (n / 1e12).toFixed(1) + " TB"
        return Math.round(n / 1e9) + " GB"
    }

    // Botón del instalador. No se reutiliza CtlButton porque aquél está hecho
    // para la barra -- 26 px de alto, letra de 11 -- y aquí los botones son lo
    // principal de una pantalla entera, no un control de una cápsula.
    component Boton: Rectangle {
        id: bot
        property string text: ""
        property bool principal: false
        property bool small: false
        signal clicked()

        implicitWidth: etiqueta.implicitWidth + (small ? 26 : 42)
        implicitHeight: small ? 30 : 42
        radius: height / 2
        opacity: enabled ? 1.0 : 0.38
        color: principal
               ? (raton.containsMouse ? Qt.lighter(raiz.acento, 1.12) : raiz.acento)
               : (raton.containsMouse ? Paleta.superficieAlta : Paleta.superficie)
        border.width: principal ? 0 : 1
        border.color: Paleta.borde
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: etiqueta
            anchors.centerIn: parent
            text: bot.text
            color: bot.principal ? Paleta.sobreAcento : Paleta.texto
            font.pixelSize: bot.small ? 12 : 14
            font.bold: true
        }

        MouseArea {
            id: raton
            anchors.fill: parent
            hoverEnabled: true
            enabled: bot.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: bot.clicked()
        }
    }

    // ------------------------------------------------------------------
    // Procesos
    // ------------------------------------------------------------------

    Process {
        id: mirarInternet
        running: true
        command: ["sh", "-c", "m-internet >/dev/null 2>&1 && echo si || echo no"]
        stdout: StdioCollector {
            onStreamFinished: raiz.hayInternet = (text.trim() === "si")
        }
    }
    Timer {
        // Se vuelve a mirar cada poco: alguien puede enchufar el cable a
        // mitad, y entonces lo que estaba atenuado tiene que despertarse solo.
        interval: 5000; running: true; repeat: true
        onTriggered: if (!raiz.instalando) mirarInternet.running = true
    }

    Process {
        id: listarDiscos
        running: true
        command: ["m-install", "--listar-discos"]
        stdout: StdioCollector {
            onStreamFinished: {
                var salida = []
                var lineas = text.split("\n")
                for (var i = 0; i < lineas.length; i++) {
                    var l = lineas[i].trim()
                    if (l === "") continue
                    var c = l.split("\t")
                    if (c.length < 3) continue
                    salida.push({ ruta: c[0], bytes: c[1], modelo: c[2],
                                  extraible: c.length > 3 && c[3] === "1" })
                }
                raiz.discos = salida
                if (salida.length > 0 && raiz.discoIdx < 0) raiz.discoIdx = 0
            }
        }
    }

    Process {
        id: escanearRed
        command: ["sh", "-c",
            "m-wifi scan >/dev/null 2>&1; sleep 2; m-wifi list 2>&1"]
        onRunningChanged: if (running) raiz.buscandoRed = true
        stdout: StdioCollector {
            onStreamFinished: {
                raiz.buscandoRed = false
                if (text.indexOf("Sin adaptador") >= 0) {
                    raiz.sinAdaptador = true
                    raiz.redes = []
                    return
                }
                raiz.sinAdaptador = false
                // iwctl pinta una tabla con cabecera y adornos. Se queda lo
                // que parece un nombre de red y se descartan los rótulos.
                var vistas = []
                var lineas = text.split("\n")
                for (var i = 0; i < lineas.length; i++) {
                    var l = lineas[i].replace(/\x1b\[[0-9;]*m/g, "").trim()
                    if (l === "" || l.indexOf("---") === 0) continue
                    if (l.indexOf("Available networks") >= 0) continue
                    if (l.indexOf("Network name") >= 0) continue
                    // "> nombre  psk  ****"  ->  el nombre es lo de en medio
                    l = l.replace(/^>\s*/, "")
                    var partes = l.split(/\s{2,}/)
                    var nombre = partes[0] ? partes[0].trim() : ""
                    if (nombre === "" || nombre.length > 40) continue
                    if (vistas.indexOf(nombre) < 0) vistas.push(nombre)
                }
                raiz.redes = vistas
            }
        }
    }

    Process {
        id: conectarRed
        stdinEnabled: true
        onStarted: { write(raiz.claveRed + "\n"); stdinEnabled = false }
        onExited: (codigo) => {
            raiz.conectandoRed = false
            if (codigo !== 0) raiz.errorRed = raiz.t("redFallo")
            mirarInternet.running = true
        }
    }

    Process {
        id: aplicarFondo
        // m-fondo guarda la ruta en los ajustes, así que el fondo elegido
        // aquí sigue puesto después de instalar y de reiniciar.
        command: ["sh", "-c", "true"]
    }

    // El instalador de verdad. La contraseña le llega por la entrada estándar,
    // nunca como argumento: lo que va en la línea de órdenes lo ve cualquiera
    // con un "ps", y aquí hay gente delante mirando la pantalla.
    Process {
        id: instalar
        stdinEnabled: true
        onStarted: {
            write(raiz.clave + "\n")
            stdinEnabled = false
        }
        stdout: SplitParser {
            onRead: (linea) => {
                // Se limpian los colores de terminal: aquí no pintan nada.
                raiz.registro += linea.replace(/\x1b\[[0-9;]*m/g, "") + "\n"
            }
        }
        stderr: SplitParser {
            onRead: (linea) => {
                raiz.registro += linea.replace(/\x1b\[[0-9;]*m/g, "") + "\n"
            }
        }
        onExited: (codigo) => {
            raiz.instalando = false
            raiz.termino = true
            raiz.fallo = (codigo !== 0)
            raiz.paso = raiz.pasos.indexOf("listo")
        }
    }

    // "reboot" a secas no reiniciaba: bajo runit es una orden que no hace nada
    // y sale con código 0, así que el botón "Reiniciar ahora" se quedaba
    // mirando. Ahora hay un /usr/bin/reboot propio que sí funciona (ver
    // m-apagado), y se le llama por su nombre para que pase por la etapa de
    // apagado que desmonta los discos.
    Process { id: reiniciar; command: ["/usr/bin/reboot"] }

    // Qué hay dentro del disco elegido. Se relee cada vez que se cambia de
    // disco: enseñar las particiones del anterior sería la peor forma posible
    // de equivocarse.
    Process {
        id: verDisco
        stdout: StdioCollector {
            onStreamFinished: {
                var lista = []
                var actual = null
                var lineas = text.split("\n")
                for (var i = 0; i < lineas.length; i++) {
                    var l = lineas[i]
                    var t = l.trim()
                    if (t === "") continue
                    if (t.indexOf("particion=") === 0) {
                        if (actual) lista.push(actual)
                        actual = { ruta: t.substring(10), bytes: 0, fs: "",
                                   etiqueta: "", sistema: "", montada: "no" }
                    } else if (actual) {
                        var c = t.indexOf("=")
                        if (c < 0) continue
                        var k = t.substring(0, c), v = t.substring(c + 1)
                        if (k === "bytes") actual.bytes = Number(v)
                        else if (k === "fs") actual.fs = v
                        else if (k === "etiqueta") actual.etiqueta = v
                        else if (k === "sistema") actual.sistema = v
                        else if (k === "montada") actual.montada = v
                    }
                }
                if (actual) lista.push(actual)
                raiz.particiones = lista
            }
        }
    }

    Process {
        id: verLibre
        stdout: StdioCollector {
            onStreamFinished: raiz.espacioLibre = Number(text.trim()) || 0
        }
    }

    // La comprobación previa. Es la que decide si se puede pulsar "instalar",
    // y la que explica por qué no cuando no se puede.
    Process {
        id: comprobar
        onRunningChanged: if (running) raiz.comprobandoDisco = true
        stdout: StdioCollector {
            onStreamFinished: {
                var errs = [], avs = []
                var lineas = text.split("\n")
                for (var i = 0; i < lineas.length; i++) {
                    var l = lineas[i].trim()
                    if (l.indexOf("error=") === 0) errs.push(l.substring(6))
                    else if (l.indexOf("aviso=") === 0) avs.push(l.substring(6))
                }
                raiz.problemas = errs
                raiz.avisos = avs
                raiz.comprobandoDisco = false
            }
        }
    }

    // GParted a la carta. No viaja dentro de la ISO -- son casi 30 MB de
    // bibliotecas de C++ que la mayoría no va a usar nunca -- pero está en el
    // repositorio y se trae con una pulsación cuando hace falta de verdad.
    Process {
        id: traerGparted
        command: ["m-terminal", "-e", "sh", "-c",
                  "m-sudo mpm install gparted; echo; echo 'Pulsa Intro para cerrar.'; read x"]
        onExited: mirarGparted.running = true
    }
    Process {
        id: mirarGparted
        running: true
        command: ["sh", "-c", "command -v gparted >/dev/null 2>&1 && echo si || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                raiz.gpartedPuesto = (text.trim() === "si")
                raiz.bajandoGparted = false
            }
        }
    }
    Process { id: abrirGparted; command: ["m-sudo", "gparted"] }

    // Al cambiar de disco o de modo, todo lo que dependía de ellos deja de
    // valer: se vuelve a mirar en vez de arrastrar lo de antes.
    function refrescarDisco() {
        if (!discoSel) return
        // El idioma también aquí: los nombres de sistema («Arranque de
        // Windows» / «Windows boot files») los escribe la misma herramienta.
        verDisco.command = ["sh", "-c",
            "MIKEOS_LANG=" + idioma + " m-particiones ver " + discoSel.ruta]
        verDisco.running = true
        verLibre.command = ["m-particiones", "libre", discoSel.ruta]
        verLibre.running = true
        revisar()
    }
    function revisar() {
        if (!discoSel) return
        problemas = []
        avisos = []
        // El idioma va por delante: los avisos los escribe m-particiones y
        // tienen que salir en el mismo idioma que el resto de la pantalla.
        comprobar.command = ["sh", "-c",
            "MIKEOS_LANG=" + idioma + " m-particiones comprobar " +
            discoSel.ruta + " " + modo + " " + particionObjetivo]
        comprobar.running = true
    }

    // Se escucha discoSel y no discoIdx: el índice puede cambiar un instante
    // antes de que la lista de discos esté puesta, y entonces refrescarDisco()
    // se encontraba discoSel a null y salía sin hacer nada. discoSel sólo
    // cambia cuando la selección ya se puede resolver.
    onDiscoSelChanged: refrescarDisco()
    onIdiomaChanged: refrescarDisco()
    onModoChanged: revisar()
    onParticionObjetivoChanged: revisar()

    // Ayuda remota. La salida viene en "clave=valor", una por línea, para no
    // tener que interpretar frases.
    Process {
        id: accesoRemoto
        running: true
        command: ["m-acceso-remoto", "estado"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lineas = text.split("\n")
                for (var i = 0; i < lineas.length; i++) {
                    var l = lineas[i].trim()
                    var c = l.indexOf("=")
                    if (c < 0) continue
                    var k = l.substring(0, c), v = l.substring(c + 1)
                    if (k === "estado")  raiz.sshAbierto = (v === "abierto")
                    else if (k === "ip")      raiz.sshIp = v
                    else if (k === "usuario") raiz.sshUsuario = v
                    else if (k === "clave")   raiz.sshClave = v
                    else if (k === "error")   raiz.sshError = v
                }
            }
        }
    }

    function lanzarInstalacion() {
        registro = ""
        fallo = false
        termino = false
        instalando = true
        paso = pasos.indexOf("instalando")

        var orden = ["m-sudo", "m-install",
                     "--disco", discoSel.ruta,
                     "--modo", modo,
                     "--fs", fs,
                     "--equipo", equipo]
        if (modo === "reemplazar" && particionObjetivo !== "")
            orden = orden.concat(["--particion", particionObjetivo])
        orden = orden.concat(["--clave-por-entrada", "--si"])
        instalar.command = orden
        instalar.running = true
    }

    // ------------------------------------------------------------------
    // La ventana
    // ------------------------------------------------------------------
    PanelWindow {
        id: ventana
        // visible se pone a mano a propósito: sin él la ventana no llegaba a
        // crearse y el instalador corría sin enseñar nada. Todos los
        // PanelWindow del escritorio lo declaran, por lo mismo.
        visible: true
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        // Ignora el espacio que reserva la barra: el instalador ocupa la
        // pantalla entera, no lo que la barra deje libre.
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // OnDemand y no Exclusive: con Exclusive, un instalador que se quedara
        // colgado se llevaría el teclado consigo y no habría forma de cambiar
        // a otra ventana ni de cerrarlo.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Rectangle {
            anchors.fill: parent
            color: raiz.fondoBase
        }

        // Navegación por teclado. No es un extra: el touchpad de muchos
        // portátiles no funciona hasta que el sistema está instalado y tiene
        // sus controladores, así que sin esto habría gente que no podría pasar
        // de la primera pantalla. Enter avanza, Escape retrocede, y las
        // flechas mueven entre las opciones de cada pantalla.
        Item {
            id: teclado
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (raiz.pasoActual === "instalando") return

                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    if (raiz.pasoActual === "listo") { Qt.quit(); return }
                    if (raiz.pasoActual === "resumen") { raiz.lanzarInstalacion(); return }
                    if (raiz.puedeSeguir()) raiz.siguiente()
                    e.accepted = true
                } else if (e.key === Qt.Key_Escape) {
                    if (raiz.paso > 0) raiz.atras()
                    e.accepted = true
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_Right) {
                    var adelante = (e.key === Qt.Key_Right)
                    if (raiz.pasoActual === "idioma") {
                        raiz.idioma = adelante ? "es" : "en"
                        e.accepted = true
                    } else if (raiz.pasoActual === "disco" && raiz.discos.length > 1) {
                        var n = raiz.discos.length
                        raiz.discoIdx = (raiz.discoIdx + (adelante ? 1 : n - 1)) % n
                        e.accepted = true
                    }
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) {
                    if (raiz.pasoActual === "disco") {
                        raiz.fs = (raiz.fs === "btrfs") ? "ext4" : "btrfs"
                        e.accepted = true
                    }
                }
            }
        }

        // El fondo elegido, muy tenue detrás de todo: se ve al momento lo que
        // se acaba de elegir, sin salir del instalador para comprobarlo.
        Image {
            anchors.fill: parent
            source: raiz.fondoElegido !== "" ? "file://" + raiz.fondoElegido : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 480
            smooth: true
            asynchronous: true
            opacity: 0.18
            visible: status === Image.Ready
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 0

            // --- Cabecera ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 92

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 54
                    anchors.rightMargin: 54
                    spacing: 14

                    Icono {
                        nombre: "logo"
                        tamano: 22
                        color: raiz.acento
                    }
                    Text {
                        text: raiz.t("titulo")
                        color: Paleta.texto
                        font.pixelSize: 19
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }

                    // Puntos de progreso. Los dos últimos pasos (instalando y
                    // listo) no cuentan: ahí ya no se navega.
                    Row {
                        spacing: 7
                        visible: raiz.paso < raiz.pasos.indexOf("instalando")
                        Repeater {
                            model: 6
                            Rectangle {
                                width: index === raiz.paso ? 22 : 7
                                height: 7
                                radius: 4
                                color: index <= raiz.paso ? raiz.acento : Paleta.borde
                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                        }
                    }
                }
            }

            // --- Contenido ---
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: lienzo
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 108, 720)
                    height: parent.height - 20

                    // ============ IDIOMA ============
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 22
                        visible: raiz.pasoActual === "idioma"

                        Text {
                            text: raiz.t("idiomaTitulo")
                            color: Paleta.texto
                            font.pixelSize: 30
                            font.weight: Font.Light
                            Layout.alignment: Qt.AlignHCenter
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 16
                            Repeater {
                                model: [
                                    { cod: "en", nom: "English" },
                                    { cod: "es", nom: "Español" }
                                ]
                                Rectangle {
                                    width: 190; height: 76; radius: 16
                                    color: raiz.idioma === modelData.cod
                                           ? Qt.rgba(raiz.acento.r, raiz.acento.g, raiz.acento.b, 0.14)
                                           : Paleta.superficie
                                    border.width: raiz.idioma === modelData.cod ? 2 : 1
                                    border.color: raiz.idioma === modelData.cod
                                                  ? raiz.acento : Paleta.borde
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.nom
                                        color: Paleta.texto
                                        font.pixelSize: 17
                                        font.bold: raiz.idioma === modelData.cod
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: raiz.idioma = modelData.cod }
                                }
                            }
                        }

                        Text {
                            text: raiz.t("idiomaPie")
                            color: Paleta.textoTenue
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // ============ INTERNET ============
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 16
                        visible: raiz.pasoActual === "red"

                        Text {
                            text: raiz.t("redTitulo")
                            color: Paleta.texto
                            font.pixelSize: 27
                            font.weight: Font.Light
                        }
                        Text {
                            text: raiz.t("redTexto")
                            color: Paleta.textoTenue
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        // Estado actual, bien visible.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 12
                            color: Paleta.superficie
                            border.width: 1
                            border.color: raiz.hayInternet ? Paleta.ok : Paleta.borde
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                spacing: 12
                                Rectangle {
                                    width: 9; height: 9; radius: 5
                                    color: raiz.hayInternet ? Paleta.ok : Paleta.textoTenue
                                }
                                Text {
                                    text: raiz.hayInternet ? raiz.t("redConectada")
                                                           : raiz.t("redSinConexion")
                                    color: Paleta.texto
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Boton {
                                    text: raiz.buscandoRed ? raiz.t("redBuscando")
                                                           : raiz.t("redBuscar")
                                    small: true
                                    onClicked: if (!raiz.buscandoRed) escanearRed.running = true
                                }
                            }
                        }

                        Text {
                            visible: raiz.sinAdaptador
                            text: raiz.t("redSinAdaptador")
                            color: Paleta.aviso
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        // Redes encontradas.
                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(raiz.redes.length * 44, 176)
                            visible: raiz.redes.length > 0
                            contentHeight: columnaRedes.implicitHeight
                            clip: true
                            Column {
                                id: columnaRedes
                                width: parent.width
                                spacing: 6
                                Repeater {
                                    model: raiz.redes
                                    Rectangle {
                                        width: columnaRedes.width
                                        height: 38
                                        radius: 10
                                        color: raiz.redElegida === modelData
                                               ? Qt.rgba(raiz.acento.r, raiz.acento.g, raiz.acento.b, 0.14)
                                               : "transparent"
                                        border.width: 1
                                        border.color: raiz.redElegida === modelData
                                                      ? raiz.acento : Paleta.borde
                                        Row {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 14
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 10
                                            Icono { nombre: "wifi"; tamano: 14; color: Paleta.texto }
                                            Text {
                                                text: modelData
                                                color: Paleta.texto
                                                font.pixelSize: 13
                                            }
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            gesturePolicy: TapHandler.ReleaseWithinBounds
                                            onTapped: { raiz.redElegida = modelData; raiz.errorRed = "" }
                                        }
                                    }
                                }
                            }
                        }

                        // Contraseña de la red elegida.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: raiz.redElegida !== ""
                            spacing: 10
                            Rectangle {
                                Layout.fillWidth: true
                                height: 40
                                radius: 20
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.width: 1
                                border.color: claveRedCampo.activeFocus ? raiz.acento : Paleta.borde
                                TextInput {
                                    id: claveRedCampo
                                    anchors.fill: parent
                                    anchors.leftMargin: 18
                                    anchors.rightMargin: 18
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Paleta.texto
                                    font.pixelSize: 14
                                    echoMode: TextInput.Password
                                    passwordCharacter: "●"
                                    onTextChanged: raiz.claveRed = text
                                    onAccepted: conectar.pulsar()
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: claveRedCampo.text === ""
                                    text: raiz.t("redContrasena")
                                    color: Paleta.textoTenue
                                    font.pixelSize: 14
                                }
                            }
                            Boton {
                                id: conectar
                                text: raiz.conectandoRed ? raiz.t("redConectando")
                                                         : raiz.t("redConectar")
                                function pulsar() {
                                    if (raiz.conectandoRed || raiz.redElegida === "") return
                                    raiz.conectandoRed = true
                                    raiz.errorRed = ""
                                    conectarRed.command = ["m-wifi", "connect", raiz.redElegida]
                                    conectarRed.running = true
                                }
                                onClicked: pulsar()
                            }
                        }

                        Text {
                            visible: raiz.errorRed !== ""
                            text: raiz.errorRed
                            color: "#ff5c68"
                            font.pixelSize: 13
                        }

                        // --- Ayuda remota por SSH ---
                        // Grande y con su propio sitio porque es la salida para
                        // quien no se atreve solo: en vez de abandonar la
                        // instalación, llama a alguien y se la miran desde su
                        // casa. Sale aquí, en el paso de red, porque sin red no
                        // hay nada que activar.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: cajaSsh.implicitHeight + 34
                            Layout.topMargin: 10
                            radius: 15
                            color: raiz.sshAbierto
                                   ? Qt.rgba(raiz.acento.r, raiz.acento.g, raiz.acento.b, 0.10)
                                   : Paleta.superficie
                            border.width: raiz.sshAbierto ? 2 : 1
                            border.color: raiz.sshAbierto ? raiz.acento : Paleta.borde
                            Behavior on color { ColorAnimation { duration: 160 } }

                            ColumnLayout {
                                id: cajaSsh
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Icono {
                                        nombre: raiz.sshAbierto ? "cable" : "sin-red"
                                        tamano: 19
                                        color: raiz.sshAbierto ? raiz.acento : Paleta.texto
                                    }
                                    ColumnLayout {
                                        spacing: 2
                                        Layout.fillWidth: true
                                        Text {
                                            text: raiz.sshAbierto ? raiz.t("sshAbierto")
                                                                  : raiz.t("sshTitulo")
                                            color: raiz.sshAbierto ? raiz.acento : Paleta.texto
                                            font.pixelSize: 16
                                            font.bold: true
                                        }
                                        Text {
                                            text: raiz.t("sshTexto")
                                            color: Paleta.textoTenue
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                    Boton {
                                        text: raiz.sshAbierto ? raiz.t("sshCerrar")
                                                              : raiz.t("sshActivar")
                                        principal: !raiz.sshAbierto
                                        small: true
                                        enabled: raiz.sshAbierto || raiz.sshIp !== ""
                                        onClicked: {
                                            raiz.sshError = ""
                                            accesoRemoto.command = ["m-acceso-remoto",
                                                raiz.sshAbierto ? "cerrar" : "activar"]
                                            if (raiz.sshAbierto) raiz.sshClave = ""
                                            accesoRemoto.running = true
                                        }
                                    }
                                }

                                Text {
                                    visible: !raiz.sshAbierto && raiz.sshIp === ""
                                    text: raiz.t("sshSinRed")
                                    color: Paleta.aviso
                                    font.pixelSize: 12
                                }

                                // Las instrucciones, con la orden literal que hay
                                // que teclear y la contraseña al lado. Se enseña
                                // entera, no oculta: la gracia es poder dictarla.
                                ColumnLayout {
                                    visible: raiz.sshAbierto && raiz.sshClave !== ""
                                    Layout.fillWidth: true
                                    spacing: 5

                                    Text {
                                        text: raiz.t("sshComo")
                                        color: Paleta.textoTenue
                                        font.pixelSize: 12
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        radius: 8
                                        color: "#05070c"
                                        border.width: 1
                                        border.color: Paleta.borde
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 14
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "ssh " + raiz.sshUsuario + "@" + raiz.sshIp
                                            color: raiz.acento
                                            font.family: "monospace"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Text {
                                            text: raiz.t("sshClaveEs")
                                            color: Paleta.textoTenue
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            text: raiz.sshClave
                                            color: Paleta.texto
                                            font.family: "monospace"
                                            font.pixelSize: 15
                                            font.bold: true
                                            font.letterSpacing: 1
                                        }
                                    }
                                    Text {
                                        text: raiz.t("sshPorQueClave")
                                        color: Paleta.textoTenue
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                        topPadding: 3
                                    }
                                    Text {
                                        text: raiz.t("sshAviso")
                                        color: Paleta.aviso
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                Text {
                                    visible: raiz.sshError !== ""
                                    text: raiz.sshError
                                    color: "#ff5c68"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    // ============ DISCO ============
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 16
                        visible: raiz.pasoActual === "disco"

                        Text {
                            text: raiz.t("discoTitulo")
                            color: Paleta.texto
                            font.pixelSize: 27
                            font.weight: Font.Light
                        }
                        Text {
                            text: raiz.t("discoTexto")
                            color: Paleta.textoTenue
                            font.pixelSize: 14
                        }

                        Text {
                            visible: raiz.discos.length === 0
                            text: raiz.t("discoNinguno")
                            color: Paleta.aviso
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: raiz.discos
                                Rectangle {
                                    width: parent.width
                                    height: 66
                                    radius: 13
                                    color: raiz.discoIdx === index
                                           ? Qt.rgba(raiz.acento.r, raiz.acento.g, raiz.acento.b, 0.12)
                                           : Paleta.superficie
                                    border.width: raiz.discoIdx === index ? 2 : 1
                                    border.color: raiz.discoIdx === index ? raiz.acento : Paleta.borde
                                    Behavior on color { ColorAnimation { duration: 130 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 18
                                        anchors.rightMargin: 18
                                        spacing: 14
                                        Icono { nombre: "sistema"; tamano: 20; color: Paleta.texto }
                                        ColumnLayout {
                                            spacing: 1
                                            Text {
                                                text: modelData.modelo + "  ·  " + raiz.bytesLegibles(modelData.bytes)
                                                color: Paleta.texto
                                                font.pixelSize: 14
                                                font.bold: true
                                            }
                                            Text {
                                                text: modelData.ruta +
                                                      (modelData.extraible ? "   ⚠ " + raiz.t("discoExtraible") : "")
                                                color: modelData.extraible ? Paleta.aviso : Paleta.textoTenue
                                                font.pixelSize: 12
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: raiz.discoIdx = index }
                                }
                            }
                        }

                        // --- Cómo instalar ---
                        Text {
                            text: raiz.t("modoTitulo")
                            color: Paleta.textoTenue
                            font.pixelSize: 13
                            topPadding: 10
                            visible: raiz.discoSel !== null
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: 7
                            visible: raiz.discoSel !== null
                            Repeater {
                                model: [
                                    { id: "borrar",     t: raiz.t("modoBorrar"),
                                      s: raiz.t("modoBorrarSub") },
                                    { id: "al-lado",    t: raiz.t("modoLado"),
                                      s: raiz.t("modoLadoSub") + "  ·  " +
                                         raiz.bytesLegibles(raiz.espacioLibre) + " " +
                                         raiz.t("modoLibre") },
                                    { id: "reemplazar", t: raiz.t("modoReemplazar"),
                                      s: raiz.t("modoReemplazarSub") }
                                ]
                                Rectangle {
                                    width: parent.width
                                    height: 52
                                    radius: 12
                                    color: raiz.modo === modelData.id
                                           ? Qt.rgba(raiz.acento.r, raiz.acento.g, raiz.acento.b, 0.10)
                                           : "transparent"
                                    border.width: raiz.modo === modelData.id ? 2 : 1
                                    border.color: raiz.modo === modelData.id ? raiz.acento : Paleta.borde
                                    Behavior on color { ColorAnimation { duration: 130 } }
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 16
                                        anchors.right: parent.right
                                        anchors.rightMargin: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12
                                        Rectangle {
                                            width: 15; height: 15; radius: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: "transparent"
                                            border.width: 2
                                            border.color: raiz.modo === modelData.id ? raiz.acento : Paleta.borde
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 7; height: 7; radius: 4
                                                color: raiz.acento
                                                visible: raiz.modo === modelData.id
                                            }
                                        }
                                        Column {
                                            spacing: 1
                                            anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                text: modelData.t
                                                color: Paleta.texto
                                                font.pixelSize: 13
                                                font.bold: true
                                            }
                                            Text {
                                                text: modelData.s
                                                color: Paleta.textoTenue
                                                font.pixelSize: 11
                                            }
                                        }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: raiz.modo = modelData.id }
                                }
                            }
                        }

                        // --- Qué hay dentro del disco ---
                        // Se enseña siempre, no sólo al reemplazar: antes de
                        // borrar nada, lo primero es ver qué se va a borrar.
                        Column {
                            Layout.fillWidth: true
                            spacing: 5
                            visible: raiz.particiones.length > 0
                            Repeater {
                                model: raiz.particiones
                                Rectangle {
                                    width: parent.width
                                    height: 40
                                    radius: 9
                                    color: raiz.modo === "reemplazar" && raiz.particionObjetivo === modelData.ruta
                                           ? Qt.rgba(raiz.acento.r, raiz.acento.g, raiz.acento.b, 0.12)
                                           : "transparent"
                                    border.width: 1
                                    border.color: raiz.modo === "reemplazar" && raiz.particionObjetivo === modelData.ruta
                                                  ? raiz.acento : Paleta.borde
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12
                                        Text {
                                            text: modelData.ruta
                                            color: Paleta.texto
                                            font.family: "monospace"
                                            font.pixelSize: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: raiz.bytesLegibles(modelData.bytes)
                                            color: Paleta.textoTenue
                                            font.pixelSize: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: modelData.fs
                                            color: Paleta.textoTenue
                                            font.pixelSize: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            visible: modelData.sistema !== "" &&
                                                     modelData.sistema !== "desconocido"
                                            text: modelData.sistema
                                            color: raiz.acento
                                            font.pixelSize: 12
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    HoverHandler {
                                        enabled: raiz.modo === "reemplazar"
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    TapHandler {
                                        gesturePolicy: TapHandler.ReleaseWithinBounds
                                        enabled: raiz.modo === "reemplazar"
                                        onTapped: raiz.particionObjetivo = modelData.ruta
                                    }
                                }
                            }
                        }

                        // --- Lo que impide seguir, y por qué ---
                        // Sale AQUÍ, en el paso del disco, y no al final: de
                        // nada sirve enterarte de que falta la partición EFI
                        // cuando ya le has dado a instalar.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: colProblemas.implicitHeight + 26
                            visible: raiz.problemas.length > 0 || raiz.avisos.length > 0
                            radius: 12
                            color: raiz.problemas.length > 0
                                   ? Qt.rgba(1, 0.36, 0.41, 0.10)
                                   : Qt.rgba(0.89, 0.63, 0.24, 0.10)
                            border.width: 1
                            border.color: raiz.problemas.length > 0 ? "#ff5c68" : Paleta.aviso
                            Column {
                                id: colProblemas
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 6
                                Text {
                                    visible: raiz.problemas.length > 0
                                    text: raiz.t("revisarTitulo")
                                    color: "#ff5c68"
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                                Repeater {
                                    model: raiz.problemas
                                    Text {
                                        width: colProblemas.width
                                        text: "·  " + modelData
                                        color: "#ff5c68"
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                }
                                Repeater {
                                    model: raiz.avisos
                                    Text {
                                        width: colProblemas.width
                                        text: "·  " + modelData
                                        color: Paleta.aviso
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // --- Particionado avanzado ---
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            Layout.topMargin: 4
                            radius: 12
                            color: "transparent"
                            border.width: 1
                            border.color: Paleta.borde
                            opacity: (raiz.gpartedPuesto || raiz.hayInternet) ? 1.0 : 0.45
                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12
                                Icono { nombre: "sistema"; tamano: 16; color: Paleta.textoTenue
                                        anchors.verticalCenter: parent.verticalCenter }
                                Column {
                                    spacing: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        text: raiz.t("avanzado")
                                        color: Paleta.texto
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                    Text {
                                        text: raiz.t("avanzadoSub")
                                        color: Paleta.textoTenue
                                        font.pixelSize: 11
                                    }
                                }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                Text {
                                    visible: !raiz.gpartedPuesto && !raiz.hayInternet
                                    text: raiz.t("avanzadoRed")
                                    color: Paleta.aviso
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Boton {
                                    small: true
                                    visible: raiz.gpartedPuesto || raiz.hayInternet
                                    text: raiz.gpartedPuesto ? raiz.t("avanzadoAbrir")
                                        : (raiz.bajandoGparted ? raiz.t("avanzadoBajando")
                                                               : raiz.t("avanzadoInstalar"))
                                    onClicked: {
                                        if (raiz.gpartedPuesto) { abrirGparted.running = true }
                                        else if (!raiz.bajandoGparted) {
                                            raiz.bajandoGparted = true
                                            traerGparted.running = true
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            text: raiz.t("discoFs")
                            color: Paleta.textoTenue
                            font.pixelSize: 13
                            topPadding: 6
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: [
                                    { id: "btrfs", txt: raiz.t("discoBtrfs") },
                                    { id: "ext4",  txt: raiz.t("discoExt4") }
                                ]
                                Rectangle {
                                    width: parent.width
                                    height: 44
                                    radius: 11
                                    color: "transparent"
                                    border.width: raiz.fs === modelData.id ? 2 : 1
                                    border.color: raiz.fs === modelData.id ? raiz.acento : Paleta.borde
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12
                                        Rectangle {
                                            width: 15; height: 15; radius: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: "transparent"
                                            border.width: 2
                                            border.color: raiz.fs === modelData.id ? raiz.acento : Paleta.borde
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 7; height: 7; radius: 4
                                                color: raiz.acento
                                                visible: raiz.fs === modelData.id
                                            }
                                        }
                                        Text {
                                            text: modelData.txt
                                            color: Paleta.texto
                                            font.pixelSize: 13
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: raiz.fs = modelData.id }
                                }
                            }
                        }
                    }

                    // ============ CUENTA ============
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 14
                        visible: raiz.pasoActual === "cuenta"

                        Text {
                            text: raiz.t("cuentaTitulo")
                            color: Paleta.texto
                            font.pixelSize: 27
                            font.weight: Font.Light
                            bottomPadding: 6
                        }

                        Text { text: raiz.t("cuentaEquipo"); color: Paleta.textoTenue; font.pixelSize: 13 }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 44; radius: 22
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.width: 1
                            border.color: equipoCampo.activeFocus ? raiz.acento : Paleta.borde
                            TextInput {
                                id: equipoCampo
                                anchors.fill: parent
                                anchors.leftMargin: 20; anchors.rightMargin: 20
                                verticalAlignment: TextInput.AlignVCenter
                                color: Paleta.texto
                                font.pixelSize: 15
                                text: raiz.equipo
                                // Lo que va en /etc/hostname no admite espacios
                                // ni mayúsculas sin dar problemas de red.
                                validator: RegularExpressionValidator {
                                    regularExpression: /[a-z0-9-]{0,32}/
                                }
                                onTextChanged: raiz.equipo = text
                            }
                        }

                        Text {
                            text: raiz.t("cuentaClave")
                            color: Paleta.textoTenue
                            font.pixelSize: 13
                            topPadding: 8
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 44; radius: 22
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.width: 1
                            border.color: claveCampo.activeFocus ? raiz.acento : Paleta.borde
                            TextInput {
                                id: claveCampo
                                anchors.fill: parent
                                anchors.leftMargin: 20; anchors.rightMargin: 20
                                verticalAlignment: TextInput.AlignVCenter
                                color: Paleta.texto
                                font.pixelSize: 15
                                echoMode: TextInput.Password
                                passwordCharacter: "●"
                                onTextChanged: raiz.clave = text
                            }
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 20
                                anchors.verticalCenter: parent.verticalCenter
                                visible: claveCampo.text === ""
                                text: raiz.t("cuentaSinClave")
                                color: Paleta.textoTenue
                                font.pixelSize: 14
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 44; radius: 22
                            visible: raiz.clave !== ""
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.width: 1
                            border.color: raiz.clave2 !== "" && raiz.clave !== raiz.clave2
                                          ? "#ff5c68"
                                          : (clave2Campo.activeFocus ? raiz.acento : Paleta.borde)
                            TextInput {
                                id: clave2Campo
                                anchors.fill: parent
                                anchors.leftMargin: 20; anchors.rightMargin: 20
                                verticalAlignment: TextInput.AlignVCenter
                                color: Paleta.texto
                                font.pixelSize: 15
                                echoMode: TextInput.Password
                                passwordCharacter: "●"
                                onTextChanged: raiz.clave2 = text
                            }
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 20
                                anchors.verticalCenter: parent.verticalCenter
                                visible: clave2Campo.text === ""
                                text: raiz.t("cuentaRepetir")
                                color: Paleta.textoTenue
                                font.pixelSize: 14
                            }
                        }

                        Text {
                            visible: raiz.clave !== "" && raiz.clave2 !== "" && raiz.clave !== raiz.clave2
                            text: raiz.t("cuentaNoCoincide")
                            color: "#ff5c68"
                            font.pixelSize: 13
                        }
                        Text {
                            visible: raiz.clave === ""
                            text: raiz.t("cuentaAvisoVacia")
                            color: Paleta.aviso
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    // ============ ASPECTO ============
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 14
                        visible: raiz.pasoActual === "aspecto"

                        Text {
                            text: raiz.t("aspectoTitulo")
                            color: Paleta.texto
                            font.pixelSize: 27
                            font.weight: Font.Light
                        }
                        Text {
                            text: raiz.t("aspectoTexto")
                            color: Paleta.textoTenue
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        // Los fondos que trae el sistema. El primero es el de
                        // fábrica; los demás salen de /usr/share/backgrounds.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 10
                            Repeater {
                                model: raiz.fondosDisponibles
                                Rectangle {
                                    width: 148; height: 88; radius: 11
                                    color: Paleta.superficie
                                    border.width: raiz.fondoElegido === modelData.ruta ? 2 : 1
                                    border.color: raiz.fondoElegido === modelData.ruta
                                                  ? raiz.acento : Paleta.borde
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        source: "file://" + modelData.ruta
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize.width: 296
                                        asynchronous: true
                                    }
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 22
                                        color: Qt.rgba(0, 0, 0, 0.6)
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.nombre
                                            color: Paleta.texto
                                            font.pixelSize: 11
                                        }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: raiz.fondoElegido = modelData.ruta }
                                }
                            }
                        }

                        // Colores del sistema sacados del fondo.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 66
                            radius: 13
                            color: raiz.coloresDelFondo
                                   ? Qt.rgba(raiz.acento.r, raiz.acento.g, raiz.acento.b, 0.10)
                                   : Paleta.superficie
                            border.width: 1
                            border.color: raiz.coloresDelFondo ? raiz.acento : Paleta.borde
                            Behavior on color { ColorAnimation { duration: 140 } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18; anchors.rightMargin: 18
                                spacing: 14
                                ColumnLayout {
                                    spacing: 2
                                    Text {
                                        text: raiz.t("aspectoColores")
                                        color: Paleta.texto
                                        font.pixelSize: 14
                                        font.bold: true
                                    }
                                    Text {
                                        text: raiz.t("aspectoColoresTexto")
                                        color: Paleta.textoTenue
                                        font.pixelSize: 12
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                // Interruptor
                                Rectangle {
                                    width: 46; height: 25; radius: 13
                                    color: raiz.coloresDelFondo ? raiz.acento : Paleta.borde
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Rectangle {
                                        width: 19; height: 19; radius: 10
                                        color: Paleta.texto
                                        y: 3
                                        x: raiz.coloresDelFondo ? parent.width - 22 : 3
                                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: raiz.coloresDelFondo = !raiz.coloresDelFondo }
                                }
                            }
                        }

                        // Lo que necesita internet se enseña atenuado y DICE
                        // por qué, en vez de desaparecer o fallar al pulsarlo.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            radius: 12
                            color: "transparent"
                            border.width: 1
                            border.color: Paleta.borde
                            opacity: raiz.hayInternet ? 1.0 : 0.45
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18; anchors.rightMargin: 18
                                spacing: 12
                                Icono { nombre: "wifi"; tamano: 15; color: Paleta.textoTenue }
                                Text {
                                    text: raiz.t("aspectoMasFondos")
                                    color: Paleta.texto
                                    font.pixelSize: 13
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    visible: !raiz.hayInternet
                                    text: raiz.t("aspectoNecesitaRed")
                                    color: Paleta.aviso
                                    font.pixelSize: 12
                                }
                                Boton {
                                    visible: raiz.hayInternet
                                    text: "m-wallhaven"
                                    small: true
                                    onClicked: abrirWallhaven.running = true
                                }
                            }
                        }
                    }

                    // ============ RESUMEN ============
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 12
                        visible: raiz.pasoActual === "resumen"

                        Text {
                            text: raiz.t("resumenTitulo")
                            color: Paleta.texto
                            font.pixelSize: 27
                            font.weight: Font.Light
                            bottomPadding: 6
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: filas.implicitHeight + 30
                            radius: 14
                            color: Paleta.superficie
                            border.width: 1
                            border.color: Paleta.borde
                            ColumnLayout {
                                id: filas
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 22
                                anchors.rightMargin: 22
                                spacing: 9
                                Repeater {
                                    model: [
                                        { k: raiz.t("resumenDisco"),
                                          v: raiz.discoSel ? (raiz.discoSel.ruta + "  ·  " +
                                             raiz.bytesLegibles(raiz.discoSel.bytes)) : "—" },
                                        { k: raiz.t("resumenFs"),     v: raiz.fs },
                                        { k: raiz.t("resumenEquipo"), v: raiz.equipo },
                                        { k: raiz.t("resumenClave"),
                                          v: raiz.clave !== "" ? raiz.t("resumenSi") : raiz.t("resumenNo") },
                                        { k: raiz.t("resumenFondo"),
                                          v: raiz.fondoElegido === "" ? raiz.t("aspectoDefecto")
                                             : raiz.fondoElegido.split("/").pop() },
                                        { k: raiz.t("resumenRed"),
                                          v: raiz.hayInternet ? raiz.t("redConectada") : raiz.t("redSinConexion") }
                                    ]
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.k
                                            color: Paleta.textoTenue
                                            font.pixelSize: 13
                                            Layout.preferredWidth: 190
                                        }
                                        Text {
                                            text: modelData.v
                                            color: Paleta.texto
                                            font.pixelSize: 13
                                            font.bold: true
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            text: raiz.t("resumenAviso")
                            color: "#ff5c68"
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            topPadding: 4
                        }
                    }

                    // ============ INSTALANDO ============
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 30
                        anchors.bottomMargin: 20
                        spacing: 14
                        visible: raiz.pasoActual === "instalando"

                        Text {
                            text: raiz.t("instalandoTitulo")
                            color: Paleta.texto
                            font.pixelSize: 27
                            font.weight: Font.Light
                        }
                        Text {
                            text: raiz.t("instalandoTexto")
                            color: Paleta.textoTenue
                            font.pixelSize: 14
                        }

                        // Barra indeterminada: no se sabe cuánto falta -- copiar
                        // el sistema depende del disco -- y una barra que miente
                        // es peor que una que sólo dice "sigo trabajando".
                        Rectangle {
                            id: barraPulso
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: Paleta.borde
                            clip: true
                            Rectangle {
                                id: pulso
                                width: parent.width * 0.3
                                height: parent.height
                                radius: 2
                                color: raiz.acento
                                // Dentro de una animación no hay "parent": se
                                // referencian los ítems por su id.
                                SequentialAnimation on x {
                                    running: raiz.instalando
                                    loops: Animation.Infinite
                                    NumberAnimation { from: -pulso.width
                                                      to: barraPulso.width
                                                      duration: 1400
                                                      easing.type: Easing.InOutQuad }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: "#05070c"
                            border.width: 1
                            border.color: Paleta.borde
                            Flickable {
                                id: vistaRegistro
                                anchors.fill: parent
                                anchors.margins: 14
                                contentHeight: textoRegistro.implicitHeight
                                clip: true
                                // Sigue al final solo: quien mira esto quiere
                                // ver lo último, no buscarlo con la rueda.
                                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                                Text {
                                    id: textoRegistro
                                    width: vistaRegistro.width
                                    text: raiz.registro
                                    color: Paleta.textoTenue
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    // ============ LISTO / FALLO ============
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 18
                        visible: raiz.pasoActual === "listo"

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 76; height: 76; radius: 38
                            color: "transparent"
                            border.width: 2
                            border.color: raiz.fallo ? "#ff5c68" : Paleta.ok
                            Icono {
                                anchors.centerIn: parent
                                nombre: raiz.fallo ? "sin-red" : "check"
                                tamano: 34
                                color: raiz.fallo ? "#ff5c68" : Paleta.ok
                            }
                        }

                        Text {
                            text: raiz.fallo ? raiz.t("falloTitulo") : raiz.t("listoTitulo")
                            color: Paleta.texto
                            font.pixelSize: 27
                            font.weight: Font.Light
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: raiz.fallo ? raiz.t("falloTexto") : raiz.t("listoTexto")
                            color: Paleta.textoTenue
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        // Si ha fallado, el registro se queda a la vista: es lo
                        // único con lo que alguien puede averiguar qué pasó.
                        Rectangle {
                            visible: raiz.fallo
                            Layout.fillWidth: true
                            Layout.preferredHeight: 190
                            radius: 12
                            color: "#05070c"
                            border.width: 1
                            border.color: Paleta.borde
                            Flickable {
                                id: vistaFallo
                                anchors.fill: parent
                                anchors.margins: 14
                                contentHeight: textoFallo.implicitHeight
                                clip: true
                                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                                Text {
                                    id: textoFallo
                                    width: vistaFallo.width
                                    text: raiz.registro
                                    color: Paleta.textoTenue
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12
                            Boton {
                                visible: !raiz.fallo
                                text: raiz.t("listoReiniciar")
                                onClicked: reiniciar.running = true
                            }
                            Boton {
                                text: raiz.t("listoCerrar")
                                onClicked: Qt.quit()
                            }
                        }
                    }
                }
            }

            // --- Pie con la navegación ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 88
                visible: raiz.pasoActual !== "instalando" && raiz.pasoActual !== "listo"

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: Paleta.borde
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 54
                    anchors.rightMargin: 54
                    spacing: 12

                    Boton {
                        text: raiz.t("cancelar")
                        onClicked: Qt.quit()
                    }
                    Item { Layout.fillWidth: true }
                    Boton {
                        visible: raiz.paso > 0
                        text: raiz.t("atras")
                        onClicked: raiz.atras()
                    }
                    // Saltar la red es una decisión explícita, no un "siguiente"
                    // cualquiera: se dice lo que significa.
                    Boton {
                        visible: raiz.pasoActual === "red" && !raiz.hayInternet
                        text: raiz.t("redSaltar")
                        onClicked: raiz.siguiente()
                    }
                    Boton {
                        text: raiz.pasoActual === "resumen" ? raiz.t("resumenInstalar")
                                                            : raiz.t("siguiente")
                        principal: true
                        enabled: raiz.puedeSeguir()
                        opacity: raiz.puedeSeguir() ? 1.0 : 0.4
                        onClicked: {
                            if (raiz.pasoActual === "resumen") raiz.lanzarInstalacion()
                            else raiz.siguiente()
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Fondos disponibles
    // ------------------------------------------------------------------
    property var fondosDisponibles: []
    Process {
        id: listarFondos
        running: true
        command: ["sh", "-c",
            "ls -1 /usr/share/backgrounds/*.png /usr/share/backgrounds/*.jpg " +
            "~/.config/mike/fondos/* 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var salida = []
                var lineas = text.split("\n")
                for (var i = 0; i < lineas.length; i++) {
                    var l = lineas[i].trim()
                    if (l === "") continue
                    var nom = l.split("/").pop().replace(/\.[a-zA-Z]+$/, "")
                    if (l.indexOf("/usr/share/backgrounds/wallpaper.png") === 0)
                        nom = raiz.t("aspectoDefecto")
                    salida.push({ ruta: l, nombre: nom })
                }
                raiz.fondosDisponibles = salida
                // El de fábrica va elegido de salida: así el resumen nunca
                // dice "ninguno" y el sistema arranca con fondo pase lo que pase.
                if (raiz.fondoElegido === "" && salida.length > 0)
                    raiz.fondoElegido = salida[0].ruta
            }
        }
    }

    Process { id: abrirWallhaven; command: ["m-terminal", "-e", "m-wallhaven"] }
}
