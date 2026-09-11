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
for _ in $(seq 1 40); do
    if [ -n "$(vm 'pgrep -x quickshell')" ]; then break; fi
    printf "."
    sleep 3
done
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

# --- Centro de Control, con clics de verdad ---------------------------------
# Es la única forma de cazar cosas como "pulsar un apartado cierra el panel":
# el código está bien, el comportamiento no.
echo "Centro de Control (clics reales)"
if [ -S "$QMP" ]; then
    clic() { python3 "$RAIZ/tests/clic.py" "$1" "$2" >/dev/null 2>&1; }

    # Escritorio a solas, para tener con qué comparar.
    clic 960 1000; sleep 2
    vm 'grim /tmp/humo-cerrado.png >/dev/null 2>&1'

    clic 1888 23; sleep 3
    vm 'grim /tmp/humo-abierto.png >/dev/null 2>&1'

    printf '  %-46s' "el Centro de Control abre al pulsar su botón"
    if [ -n "$(vm 'cmp -s /tmp/humo-cerrado.png /tmp/humo-abierto.png || echo distintas')" ]; then
        echo "$(verde ✓)"; PASAN=$((PASAN + 1))
    else
        echo "$(rojo ✗)"; FALLAN=$((FALLAN + 1)); FALLOS+=("el panel no abre")
    fi

    # Y el fallo concreto que se arregló: al pulsar un apartado, el panel se
    # cerraba entero. Si vuelve a pasar, esta captura será igual que la del
    # escritorio a solas.
    clic 570 385; sleep 3
    vm 'grim /tmp/humo-seccion.png >/dev/null 2>&1'

    printf '  %-46s' "el panel sigue abierto al cambiar de apartado"
    if [ -n "$(vm 'cmp -s /tmp/humo-cerrado.png /tmp/humo-seccion.png || echo distintas')" ]; then
        echo "$(verde ✓)"; PASAN=$((PASAN + 1))
    else
        echo "$(rojo ✗)  $(gris "la pantalla volvió al escritorio: se cerró")"
        FALLAN=$((FALLAN + 1)); FALLOS+=("el panel se cierra al cambiar de apartado")
    fi

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
