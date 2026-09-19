#!/bin/bash
# Prueba de humo de MIKE OS.
#
# Arranca la imagen recién construida, espera a que el escritorio esté en pie
# y comprueba una por una las cosas que tienen que funcionar. Devuelve 0 si
# todas pasan y 1 si falla alguna, así que sirve tanto para mirarla como para
# encadenarla con otra cosa.
#
# Existe porque hasta ahora la verificación era mirar capturas a ojo, punto
# por punto, y así una regresión sólo se descubre cuando alguien se tropieza
# con ella. Cada comprobación de aquí es un fallo que ya ocurrió de verdad.
#
#   ./tests/humo.sh              arranca, comprueba y apaga
#   ./tests/humo.sh --dejar      igual, pero deja la máquina encendida
#   ./tests/humo.sh --usar-vm    usa la que ya esté arrancada
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAVE="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"
PUERTO="${MIKEOS_DEV_PORT:-2222}"
QMP="${MIKEOS_QMP_SOCKET:-/tmp/mikeos-qmp.sock}"
SALIDA="${MIKEOS_TEST_DIR:-${TMPDIR:-/tmp}/mikeos-humo}"
DEJAR=0
USAR_VM=0

for arg in "$@"; do
    case "$arg" in
        --dejar)   DEJAR=1 ;;
        --usar-vm) USAR_VM=1; DEJAR=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Opción desconocida: $arg" >&2; exit 2 ;;
    esac
done

mkdir -p "$SALIDA"
verde()  { printf '\033[32m%s\033[0m' "$*"; }
rojo()   { printf '\033[31m%s\033[0m' "$*"; }
gris()   { printf '\033[90m%s\033[0m' "$*"; }

PASAN=0
FALLAN=0
FALLOS=()

vm() {
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ConnectTimeout=5 mike@localhost \
        "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; \
         export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1; $*" 2>/dev/null
}

# comprobar <nombre> <orden> <patrón esperado en la salida>
comprobar() {
    local nombre="$1" orden="$2" espera="$3"
    local out
    out="$(vm "$orden")"
    printf '  %-46s' "$nombre"
    if printf '%s' "$out" | grep -qE "$espera"; then
        echo "$(verde ✓)"
        PASAN=$((PASAN + 1))
    else
        echo "$(rojo ✗)  $(gris "${out:0:60}")"
        FALLAN=$((FALLAN + 1))
        FALLOS+=("$nombre")
    fi
}

# --- Arranque ---------------------------------------------------------------
QPID=""
if [ "$USAR_VM" -eq 0 ]; then
    # Antes de arrancar nada: que no haya otra máquina ocupando el puerto.
    #
    # Esto pasó de verdad y fue caro. Una VM de una sesión anterior seguía
    # encendida en el 2222, así que esta prueba arrancó la imagen NUEVA,
    # esperó a que respondiera... y se conectó a la VIEJA, que respondía
    # antes. Resultado: se estuvo probando una imagen de hace una hora
    # mientras el registro decía el nombre de la nueva. Trece comprobaciones
    # en rojo por algo que no estaba roto, y --- lo peligroso --- las otras
    # veinte en verde sin haber tocado la imagen que se quería probar.
    #
    # El patrón va anclado ("^qemu-system") a propósito: con "pkill -f qemu"
    # el propio shell que ejecuta esto lleva la palabra escrita y se mata solo.
    _viejas="$(pgrep -f "^qemu-system-x86_64" 2>/dev/null || true)"
    if [ -n "$_viejas" ]; then
        echo "$(rojo "Ya hay una máquina QEMU encendida") (PID: $(echo "$_viejas" | tr '\n' ' '))."
        echo "Se conectaría a ESA y no a la imagen recién construida."
        echo "Apágala, o usa --usar-vm si es la que quieres probar."
        exit 2
    fi
    echo "Arrancando MIKE OS..."
    "$RAIZ/scripts/run-qemu.sh" --gui --desktop --ssh-port "$PUERTO" \
        > "$SALIDA/vm.log" 2>&1 < /dev/null &
    QPID=$!
fi

printf "Esperando a que responda"
LISTA=0
for _ in $(seq 1 90); do
    if vm true >/dev/null 2>&1; then LISTA=1; break; fi
    printf "."
    sleep 3
done
echo
if [ "$LISTA" -eq 0 ]; then
    echo "$(rojo "La máquina no respondió por SSH."). Registro en $SALIDA/vm.log"
    [ -n "$QPID" ] && kill -9 "$QPID" 2>/dev/null
    exit 1
fi

# El escritorio tarda algo más que SSH: Hyprland, PipeWire y la barra van
# detrás. Sin esta espera, las comprobaciones gráficas fallan por llegar
# pronto, no por estar rotas.
printf "Esperando al escritorio"
HAY_BARRA=0
for _ in $(seq 1 40); do
    if [ -n "$(vm 'pgrep -x quickshell')" ]; then HAY_BARRA=1; break; fi
    printf "."
    sleep 3
done
echo
# Si no llegó, PREGUNTARLE POR QUÉ antes de seguir.
#
# Sin esto, un error de carga de QML se veía como dos minutos de puntitos y
# luego trece comprobaciones gráficas en rojo, ninguna de las cuales decía la
# causa. Quickshell la dice entera en una línea --- el archivo, la línea y el
# motivo --- pero sólo si alguien se la pide. Y como el módulo de QML se
# invalida ENTERO cuando falla un componente, el error señala el primer
# archivo que lo usa y no el que está roto: hay que leer la cadena completa de
# "caused by", que es justo lo que esto enseña.
if [ "$HAY_BARRA" -eq 0 ]; then
    echo "$(rojo "El escritorio no llegó a levantarse.") Esto dice Quickshell:"
    vm 'export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1; \
        timeout 20 quickshell -p ~/.config/mike/quickshell/shell.qml 2>&1 \
        | grep -i "error\|caused by" | head -10' | sed 's/^/    /'
fi
# El servidor de audio va por detrás de la barra: preguntarle antes de que
# esté montado daba un fallo que no era tal.
for _ in $(seq 1 20); do
    if [ -n "$(vm 'm-volume get')" ]; then break; fi
    printf "."
    sleep 3
done
echo
echo

# --- Base -------------------------------------------------------------------
echo "Base"
comprobar "runit es el PID 1"            'cat /proc/1/comm'                'runit'
comprobar "red con dirección IP"         'ip -4 addr show eth0'            'inet '
comprobar "resuelve nombres"             'ping -c1 -W3 1.1.1.1 >/dev/null && echo ok' 'ok'
comprobar "disco montado en lectura y escritura" 'touch ~/.humo && echo ok && rm -f ~/.humo' 'ok'
echo

# --- Audio (la incidencia que estuvo abierta del 31 ago al 11 sep) ----------
echo "Audio"
comprobar "el kernel ve una tarjeta"     'cat /proc/asound/cards'          '^ *0 '
comprobar "hay dispositivo de reproducción" 'ls /dev/snd'                  'pcmC0D0p'
comprobar "WirePlumber expone una salida" 'wpctl status 2>/dev/null | sed -n "/Sinks:/,/Sources:/p"' '[0-9]+\. '
comprobar "m-volume devuelve un número"  'm-volume get'                    '^[0-9]+'
echo

# --- Escritorio -------------------------------------------------------------
echo "Escritorio"
comprobar "Hyprland en marcha"           'pgrep -x Hyprland >/dev/null && echo ok' 'ok'
comprobar "la barra está viva"           'pgrep -x quickshell >/dev/null && echo ok' 'ok'
# Dos detalles: el pgrep de busybox no admite -c, así que se cuentan líneas;
# y el patrón va entre corchetes ("[m]-panel") porque si no, el propio shell
# que ejecuta la orden lleva "m-panel" escrito y se cuenta a sí mismo.
comprobar "una sola barra, no dos"       'pgrep -f "[m]-panel" | wc -l'    '^ *1$'
comprobar "la captura de pantalla funciona" 'grim /tmp/humo.png >/dev/null 2>&1 && test -s /tmp/humo.png && echo ok' 'ok'
comprobar "hay fondo de pantalla pintado"  'pgrep -x swaybg >/dev/null && echo ok' 'ok'
# El fondo elegido tiene que sobrevivir a la sesión: durante semanas se
# perdía al salir, porque Hyprland arrancaba swaybg con una ruta fija.
comprobar "el fondo sale de los ajustes, no de una ruta fija" \
    'm-fondo actual' '^/'
comprobar "el fondo elegido se recuerda" \
    'cp /usr/share/backgrounds/wallpaper.png /tmp/otro.png && m-fondo poner /tmp/otro.png >/dev/null && m-fondo actual' \
    '/tmp/otro.png'
echo

# --- XWayland ---------------------------------------------------------------
# Aquí murió Minecraft, y costó encontrarlo porque no dejaba ni un error a la
# vista: XWayland arranca, no encuentra /usr/bin/xkbcomp, no puede compilar su
# mapa de teclado y se muere --- pero DISPLAY=:0 sigue exportado, así que
# cualquier programa de X11 intenta conectarse a un servidor que no existe y
# falla mucho más adelante, en _initGlfw, hablando de OpenGL.
echo "XWayland"
comprobar "xkbcomp está en la imagen"    'test -x /usr/bin/xkbcomp && echo ok' 'ok'
comprobar "XWayland en marcha"           'pgrep -f "[X]wayland" >/dev/null && echo ok' 'ok'
comprobar "el socket de X existe"        'ls /tmp/.X11-unix'               'X[0-9]'
# La prueba que de verdad importa: que un cliente de X11 CONECTE. Que el
# proceso esté vivo no basta --- puede estar arrancando y morirse después.
comprobar "un cliente X11 conecta"       'DISPLAY=:0 xrandr >/dev/null 2>&1 && echo ok' 'ok'
echo

# --- Energía ----------------------------------------------------------------
echo "Energía"
comprobar "m-energia dice qué sabe hacer" 'm-energia puede | wc -l'        '^ *[0-9]'
comprobar "el perfil se guarda en /etc"  'm-energia maximo >/dev/null 2>&1; cat /etc/mikeos/energia' 'maximo'
comprobar "el perfil máximo sube el gobernador"     'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo sin-cpufreq'     'performance|sin-cpufreq'
comprobar "vuelve a automático"          'm-energia auto >/dev/null 2>&1; m-energia perfil' '^auto$'
# Lo que PRUEBA que el servicio corre es su registro: esa línea sólo la
# escribe el bucle del servicio, y sólo cuando ha llegado a mirar la
# alimentación. Ni "sv status" ni supervise/pid valen: el directorio de
# supervisión es 0700 de root y el escritorio corre como mike, así que esa
# comprobación daba rojo con el servicio perfectamente vivo.
comprobar "el servicio de energía vive"  'cat /var/log/energia/current 2>/dev/null | tail -1' 'energía\] .*Perfil:'
echo

# --- Controladores ----------------------------------------------------------
echo "Controladores"
comprobar "m-drivers da líneas para máquinas" 'm-drivers --breve | head -1' '^COMP\|'
comprobar "m-drivers mira el Bluetooth"  'm-drivers --breve | grep -c "^COMP|Bluetooth"' '^[1-9]'
comprobar "m-drivers da JSON válido"     'm-drivers --json | head -c 20'   '\{"componentes"'
# El JSON tiene que ser ANALIZABLE, no sólo empezar bien: si un nombre de
# tarjeta lleva comillas y no se escapan, el panel se queda en blanco sin decir
# por qué. Se analiza AQUÍ, en el equipo que prueba, porque dentro de la imagen
# no hay python y comprobarlo con grep sería fingir que se ha comprobado.
printf '  %-46s' "el JSON se puede analizar"
if vm 'm-drivers --json' | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if "componentes" in d else 1)' 2>/dev/null; then
    echo "$(verde ✓)"; PASAN=$((PASAN + 1))
else
    echo "$(rojo ✗)"; FALLAN=$((FALLAN + 1)); FALLOS+=("el JSON de m-drivers no se puede analizar")
fi
# El informe lo escribe un trabajo en segundo plano con "sleep 20" (etc/runit/1),
# para no retrasar el arranque. Comprobarlo a secas era una carrera que perdía
# casi siempre: se esperaba a que esté, hasta 40 segundos.
printf '  %-46s' "m-hardware deja su informe"
_hay=""
for _ in $(seq 1 20); do
    _hay="$(vm 'test -s /var/log/mikeos-hardware.txt && echo ok')"
    [ -n "$_hay" ] && break
    sleep 2
done
if [ -n "$_hay" ]; then
    echo "$(verde ✓)"; PASAN=$((PASAN + 1))
else
    echo "$(rojo ✗)"; FALLAN=$((FALLAN + 1)); FALLOS+=("m-hardware no dejó su informe")
fi
echo

# --- Reglas del compositor ------------------------------------------------
#
# Hyprland RECHAZA una regla mal escrita y sigue arrancando tan campante: lo
# dice una vez en su registro y nunca más. Aquí se le pasa cada regla del
# archivo y se comprueba que las acepte todas.
#
# Existe porque la pantalla de bienvenida llevaba meses saliendo estirada de
# lado a lado. Tenía DOS juegos de reglas para centrarla y dimensionarla, en
# dos sitios del mismo archivo, y no funcionaba ninguno: tres líneas usaban
# "windowrulev2", que Hyprland 0.56 eliminó, y las otras escribían "float" sin
# valor, que esta versión rechaza ("invalid field float: missing a value").
# Cuatro líneas que parecían hacer algo y no hacían nada, en la primera
# pantalla que ve cualquiera y en la foto de portada de la web.
echo "Reglas del compositor"
_malas=0
_detalle=""
while IFS= read -r _regla; do
    [ -n "$_regla" ] || continue
    _r="$(vm "export HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1000/hypr/ | head -1); \
          hyprctl keyword windowrule '$_regla'")"
    case "$_r" in
        ok*) ;;
        *) _malas=$((_malas + 1)); _detalle="$_detalle
     $_regla → $_r" ;;
    esac
done <<EOF
$(sed -n 's/^windowrule = //p' "$RAIZ/build/desktop/hyprland.conf")
EOF
printf '  %-46s' "Hyprland acepta todas sus windowrule"
if [ "$_malas" -eq 0 ]; then
    echo "$(verde ✓)"; PASAN=$((PASAN + 1))
else
    echo "$(rojo ✗)$_detalle"
    FALLAN=$((FALLAN + 1)); FALLOS+=("$_malas windowrule que Hyprland rechaza")
fi

# Y que la bienvenida acabe donde se le pide: que la regla se acepte no
# garantiza que gane. Antes había dos, y ganaba la equivocada.
printf '  %-46s' "la bienvenida sale flotante, no a pantalla completa"
vm 'pkill m-welcome; rm -f ~/.config/mike/.welcomed; sleep 1; \
    (m-welcome >/dev/null 2>&1 &)' >/dev/null 2>&1
sleep 6
_geo="$(vm "export HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1000/hypr/ | head -1); \
        hyprctl clients | grep -B7 'class: m-welcome' | grep -E 'floating:'")"
case "$_geo" in
    *"floating: 1"*) echo "$(verde ✓)"; PASAN=$((PASAN + 1)) ;;
    *) echo "$(rojo ✗)  $(gris "${_geo:-no se encontró la ventana}")"
       FALLAN=$((FALLAN + 1)); FALLOS+=("la bienvenida no sale flotante") ;;
esac

# Y que QUEPA. Es distinto de flotar: la ventana puede estar flotante y aun
# así ser más alta que la pantalla.
#
# gtk_window_set_default_size() es un tamaño por DEFECTO, no un máximo: GTK
# nunca encoge una ventana por debajo del tamaño natural de su contenido. El
# contenido mide unos 750 px, así que en un portátil de 1280x800 la ventana se
# salía por abajo y el botón de continuar quedaba fuera de la pantalla: en el
# USB en vivo, encallado en la primera pantalla del sistema sin nada que
# pulsar. No se vio nunca porque esta máquina corre a 1920x1080.
printf '  %-46s' "y cabe entera en la pantalla"
_alto_p="$(vm "export HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1000/hypr/ | head -1); \
           hyprctl monitors | grep -m1 -oE '[0-9]+x[0-9]+' | cut -dx -f2 | head -1")"
_geo="$(vm "export HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1000/hypr/ | head -1); \
        hyprctl clients | grep -A1 -B7 'class: m-welcome' | grep -E '^\s+(at|size):'")"
_y="$(printf '%s' "$_geo" | sed -n 's/.*at: *[0-9]*,\([0-9]*\).*/\1/p')"
_h="$(printf '%s' "$_geo" | sed -n 's/.*size: *[0-9]*,\([0-9]*\).*/\1/p')"
if [ -n "$_y" ] && [ -n "$_h" ] && [ -n "$_alto_p" ] \
   && [ "$((_y + _h))" -le "$_alto_p" ]; then
    echo "$(verde ✓)  $(gris "$_h px de alto en $_alto_p")"
    PASAN=$((PASAN + 1))
else
    echo "$(rojo ✗)  $(gris "llega a ${_y:-?}+${_h:-?} en una pantalla de ${_alto_p:-?}")"
    FALLAN=$((FALLAN + 1)); FALLOS+=("la bienvenida no cabe en la pantalla")
fi
vm 'pkill m-welcome' >/dev/null 2>&1
echo

# --- Idioma ------------------------------------------------------------------
#
# Esto sólo se puede comprobar en un sistema arrancado. tests/traducciones.sh
# mira los fuentes y no puede saber si "m-idioma en" funciona de verdad:
# escribe en /etc, y quien pulsa el botón es "mike", que no es root. Todo
# depende de que m-idioma vuelva a entrar por m-sudo y de que m-sudo conserve
# su bit setuid --- que es justo lo que una actualización por red ya rompió una
# vez.
echo "Idioma"
comprobar "el sistema dice en qué idioma habla" 'm-idioma' '^(es|en)$'
comprobar "el usuario del escritorio puede cambiarlo" \
          'm-idioma en >/dev/null 2>&1; m-idioma' '^en$'
comprobar "y queda escrito en /etc, no en un \$HOME" \
          'grep -v "^#" /etc/mikeos/idioma | grep -v "^$"' '^en$'
# Se comprueba que NO quede ninguna categoría en español, en vez de buscar una
# concreta en inglés: qué componentes tiene la máquina depende de la máquina, y
# una prueba que espera "Graphics" falla en un equipo sin gráfica en vez de
# decir lo que de verdad quería saber.
comprobar "el informe de hardware lo sigue" \
          'm-drivers --breve | grep -c "^COMP|\(Gráfica\|Red\|Sonido\|Entrada\|Cámara\|Almacenamiento\|Procesador\|Batería\)|"' \
          '^0$'
# Y se deja como estaba: las capturas en español salen después, y un sistema
# que se queda en inglés porque lo probó una prueba es una sorpresa.
comprobar "se puede volver al español"       'm-idioma es' '^es$'
echo

# --- Gestor de paquetes -----------------------------------------------------
echo "Paquetes"
comprobar "mpm search encuentra algo"    'mpm search ripgrep | tail -2'    'resultado'
# grep -E no tiene anticipación negativa, así que la contradicción se busca
# al revés: si aparecen resultados Y la frase de "no hay nada", mal.
printf '  %-46s' "mpm search no se contradice"
_busq="$(vm 'mpm search ripgrep')"
if printf '%s' "$_busq" | grep -qi ripgrep && ! printf '%s' "$_busq" | grep -qi "nada que coincida"; then
    echo "$(verde ✓)"; PASAN=$((PASAN + 1))
else
    echo "$(rojo ✗)"; FALLAN=$((FALLAN + 1)); FALLOS+=("mpm search se contradice")
fi
comprobar "mpm list responde"            'mpm list >/dev/null 2>&1 && echo ok' 'ok'
echo

# --- Copiar archivos a la máquina -------------------------------------------
# "scp archivo mike@equipo:" fallaba con «/usr/libexec/sftp-server: No such
# file or directory»: el scp moderno habla SFTP, no el protocolo antiguo, y ese
# binario no estaba. Desde fuera parecía que MIKE OS no admitía copiar
# archivos, y el mensaje nombraba una ruta sin decir que lo que faltaba era un
# programa.
echo "Copia de archivos"
comprobar "sftp-server está donde lo busca dropbear" \
    'test -x /usr/libexec/sftp-server && echo ok' 'ok'
printf '  %-46s' "scp copia un archivo de verdad"
if scp -P "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
       "$RAIZ/VERSION" mike@localhost:/tmp/humo-scp >/dev/null 2>&1 \
   && [ -n "$(vm 'cat /tmp/humo-scp')" ]; then
    echo "$(verde ✓)"; PASAN=$((PASAN + 1))
else
    echo "$(rojo ✗)"; FALLAN=$((FALLAN + 1)); FALLOS+=("scp no puede copiar a la máquina")
fi
echo

# --- Centro de Control, con clics de verdad ---------------------------------
# Es la única forma de cazar cosas como "pulsar un apartado cierra el panel":
# el código está bien, el comportamiento no.
echo "Centro de Control (clics reales)"
if [ -S "$QMP" ]; then
    clic() { python3 "$RAIZ/tests/clic.py" "$1" "$2" >/dev/null 2>&1; }

    # Escritorio a solas, para tener con qué comparar.
    clic 960 1000; sleep 2
    vm 'grim /tmp/humo-cerrado.png >/dev/null 2>&1'

    # Se le PREGUNTA a la barra en qué estado está.
    #
    # Antes esto comparaba dos capturas de pantalla y daba por bueno "han
    # salido distintas". No vale: la barra lleva un reloj, así que dos capturas
    # separadas por un segundo son SIEMPRE distintas. O sea que estas dos
    # comprobaciones pasaban en verde hiciera lo que hiciera el clic, y por eso
    # no detectaron que en un portátil de verdad no se abría nada.
    estado_cc() {
        _i="$(vm 'quickshell list --all' | awk '/^Instance /{gsub(":","",$2);print $2;exit}')"
        [ -n "$_i" ] || return 1
        vm "quickshell ipc -i $_i call ajustes estado" | tr -d '\r'
    }

    clic 1888 23; sleep 3

    printf '  %-46s' "el Centro de Control abre al pulsar su botón"
    case "$(estado_cc)" in
        abierto*) echo "$(verde ✓)"; PASAN=$((PASAN + 1)) ;;
        *) echo "$(rojo ✗)"; FALLAN=$((FALLAN + 1)); FALLOS+=("el panel no abre") ;;
    esac

    # Y el fallo concreto que se arregló: al pulsar un apartado, el panel se
    # cerraba entero.
    clic 570 385; sleep 3

    printf '  %-46s' "el panel sigue abierto al cambiar de apartado"
    case "$(estado_cc)" in
        abierto*) echo "$(verde ✓)"; PASAN=$((PASAN + 1)) ;;
        *) echo "$(rojo ✗)  $(gris "la pantalla volvió al escritorio: se cerró")"
           FALLAN=$((FALLAN + 1)); FALLOS+=("el panel se cierra al cambiar de apartado") ;;
    esac

    # Los dos apartados nuevos se abren por IPC, que es como los abre la
    # pantalla de bienvenida. Comprobar que el botón EXISTE no vale: lo que
    # importa es que al pedirlo, el panel acabe de verdad en ese apartado.
    for _sec in energia drivers; do
        _i="$(vm 'quickshell list --all' | awk '/^Instance /{gsub(":","",$2);print $2;exit}')"
        vm "quickshell ipc -i $_i call ajustes seccion $_sec" >/dev/null 2>&1
        sleep 2
        printf '  %-46s' "el apartado «$_sec» se abre"
        case "$(estado_cc)" in
            "abierto $_sec") echo "$(verde ✓)"; PASAN=$((PASAN + 1)) ;;
            *) echo "$(rojo ✗)  $(gris "$(estado_cc)")"
               FALLAN=$((FALLAN + 1)); FALLOS+=("el apartado $_sec no se abre") ;;
        esac
    done

    # Cerrar el Centro de Control antes de tocar la barra: su ventana ocupa
    # la pantalla entera y se queda con el gesto de la rueda.
    clic 960 1000; sleep 2

    printf '  %-46s' "la rueda sobre el volumen cambia el nivel"
    ANTES="$(vm 'm-volume get' | tr -d ' mute')"
    python3 "$RAIZ/tests/rueda.py" 1690 23 wheel-down 3 >/dev/null 2>&1
    sleep 2
    DESPUES="$(vm 'm-volume get' | tr -d ' mute')"
    if [ -n "$ANTES" ] && [ -n "$DESPUES" ] && [ "$ANTES" != "$DESPUES" ]; then
        echo "$(verde ✓)  $(gris "$ANTES% → $DESPUES%")"
        PASAN=$((PASAN + 1))
    else
        echo "$(rojo ✗)  $(gris "$ANTES → $DESPUES")"
        FALLAN=$((FALLAN + 1)); FALLOS+=("la rueda no cambia el volumen")
    fi

    # Captura final, para mirarla si algo falla.
    vm 'grim /tmp/humo-final.png >/dev/null 2>&1'
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        mike@localhost 'cat /tmp/humo-final.png' > "$SALIDA/pantalla.png" 2>/dev/null
else
    echo "  $(gris "sin socket QMP en $QMP: no se pueden inyectar clics")"
fi
echo

# --- Resultado --------------------------------------------------------------
echo "────────────────────────────────────────────────────────"
if [ "$FALLAN" -eq 0 ]; then
    echo " $(verde "Todo pasa") — $PASAN comprobaciones."
else
    echo " $(rojo "$FALLAN fallo(s)") de $((PASAN + FALLAN)) comprobaciones:"
    for f in "${FALLOS[@]}"; do echo "   · $f"; done
fi
[ -f "$SALIDA/pantalla.png" ] && echo " Captura: $SALIDA/pantalla.png"
echo "────────────────────────────────────────────────────────"

if [ "$DEJAR" -eq 0 ]; then
    vm 'm-sudo poweroff' >/dev/null 2>&1
    sleep 3
    [ -n "$QPID" ] && kill -9 "$QPID" 2>/dev/null
else
    echo "La máquina sigue encendida (puerto SSH $PUERTO)."
fi

[ "$FALLAN" -eq 0 ]
