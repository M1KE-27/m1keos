#!/bin/bash
# Nota: aquí NO se usa "pgrep -x". El pgrep de BusyBox compara el patrón con la
# línea de órdenes entera, así que "-x m-welcome" no encuentra un proceso
# lanzado como "/usr/bin/m-welcome" --- que es justo como se lanza.
# ==============================================================================
# capturas.sh - saca las capturas de la web desde el sistema de verdad.
#
# Son las imágenes que se publican en m1keos.duckdns.org, así que tienen que
# salir del sistema recién construido y no de un montaje: si el escritorio
# cambia, las capturas cambian con él en la siguiente ejecución.
#
# En dos idiomas. La web inglesa enseñaba capturas en español --- lo único que
# delataba que la versión inglesa era una traducción y no un sitio propio ---
# y eso no se arreglaba en la web: hay que volver a sacarlas con el escritorio
# hablando inglés.
#
# Requiere una VM arrancada con escritorio:  ./tests/humo.sh --dejar
#
#   ./scripts/capturas.sh                 en español, a capturas/
#   ./scripts/capturas.sh --idioma en     en inglés,  a capturas/en/
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAVE="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"
PUERTO="${MIKEOS_DEV_PORT:-2222}"
IDIOMA="es"
SALIDA=""

while [ $# -gt 0 ]; do
    case "$1" in
        --idioma) IDIOMA="${2:-es}"; shift 2 ;;
        -h|--help) sed -n '5,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) SALIDA="$1"; shift ;;
    esac
done
case "$IDIOMA" in es|en) ;; *) echo "Idioma no soportado: $IDIOMA"; exit 1 ;; esac

# El español manda en la raíz y el inglés cuelga de en/, igual que la web: así
# una captura nueva no obliga a tocar el generador, que ya resuelve las rutas
# por idioma.
if [ -z "$SALIDA" ]; then
    if [ "$IDIOMA" = "es" ]; then SALIDA="$RAIZ/build/web/capturas"
    else                          SALIDA="$RAIZ/build/web/capturas/en"; fi
fi

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }
rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }

vm() {
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 \
        mike@localhost \
        "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; \
         export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1; $*" 2>/dev/null
}

FALLOS=0
sacar() {  # sacar <nombre> <descripción>
    vm "grim /tmp/cap.png >/dev/null 2>&1"
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        mike@localhost 'cat /tmp/cap.png' > "$SALIDA/$1.png" 2>/dev/null
    if [ -s "$SALIDA/$1.png" ]; then
        verde "  $1.png  ($2)"
    else
        rojo "  $1 falló"
        FALLOS=$((FALLOS + 1))
    fi
}

clic() { python3 "$RAIZ/tests/clic.py" "$1" "$2" >/dev/null 2>&1; sleep 3; }

vm true >/dev/null 2>&1 || { echo "No hay VM en el puerto $PUERTO."; exit 1; }
mkdir -p "$SALIDA"

# ---------------------------------------------------------------- el idioma
#
# Se pone ANTES de sacar nada. El Centro de Control y la barra reaccionan
# solos (vigilan /etc/mikeos/idioma), pero la bienvenida está escrita en GTK
# y lee el idioma una vez al arrancar: hay que volver a lanzarla.
paso "Poniendo el escritorio en '$IDIOMA'"
vm "m-idioma $IDIOMA" >/dev/null 2>&1
ACTUAL="$(vm 'm-idioma' | tr -d '\r\n')"
if [ "$ACTUAL" != "$IDIOMA" ]; then
    rojo "El sistema dice estar en '$ACTUAL' y se pidió '$IDIOMA'. Se aborta:"
    rojo "sacar capturas en el idioma equivocado es peor que no sacarlas."
    exit 1
fi
sleep 3

paso "Sacando capturas ($IDIOMA) en $SALIDA"

# 1. La bienvenida, que es lo primero que ve alguien. Se relanza a propósito:
#    el flag .welcomed la deja salir sólo el primer arranque, y aquí hace
#    falta en cada pasada.
# Se lanza directamente y no con "hyprctl dispatch exec": hyprctl necesita
# HYPRLAND_INSTANCE_SIGNATURE, que no existe en una sesión de SSH, así que
# devolvía "is hyprland running?" y la bienvenida no llegaba a abrirse ---
# sin que nada lo dijera, porque la salida iba a /dev/null. m-welcome sólo
# necesita WAYLAND_DISPLAY, que sí está exportado.
vm 'rm -f ~/.config/mike/.welcomed; pkill m-welcome; sleep 1; (m-welcome >/dev/null 2>&1 &)' >/dev/null 2>&1
sleep 6
if [ -n "$(vm 'pgrep m-welcome')" ]; then
    sacar "bienvenida" "pantalla de inicio"
    # Y cerrarla por el proceso, no pulsando su botón.
    #
    # Aquí había un clic en unas coordenadas calculadas para una ventana de
    # 880x580 centrada. En cuanto la ventana cambió de tamaño, el clic pasó a
    # caer en el vacío: la bienvenida se quedaba abierta encima y las SIETE
    # capturas siguientes --- todos los apartados del Centro de Control ---
    # salían siendo la misma foto de la bienvenida. Sin un solo error.
    #
    # Una captura que depende de dónde cae un píxel se rompe en silencio cada
    # vez que alguien cambia un tamaño.
    vm 'pkill m-welcome' >/dev/null 2>&1
    sleep 2
else
    rojo "  la bienvenida no llegó a abrirse"
    FALLOS=$((FALLOS + 1))
fi

# 2. El escritorio con la barra.
sacar "escritorio" "escritorio y barra"

# 3. El Centro de Control, apartado por apartado.
#
#    Se abre por IPC y no por clic en el icono de la barra: el icono se mueve
#    de sitio en cuanto alguien cambia la barra de lado o le quita un módulo,
#    y una captura que depende de dónde cayó un icono se rompe en silencio.
vm 'quickshell ipc --path ~/.config/mike/quickshell/shell.qml call ajustes abrir' >/dev/null 2>&1; sleep 3
sacar "centro-de-control" "Centro de Control"
for SEC in escritorio barra bloqueo energia drivers; do
    vm "quickshell ipc --path ~/.config/mike/quickshell/shell.qml call ajustes seccion $SEC" >/dev/null 2>&1
    # Los controladores tardan: el análisis lee /sys entero.
    if [ "$SEC" = "drivers" ]; then sleep 12; else sleep 3; fi
    sacar "ajustes-$SEC" "ajustes: $SEC"
done
vm 'quickshell ipc --path ~/.config/mike/quickshell/shell.qml call ajustes cerrar' >/dev/null 2>&1; sleep 2

# 4. Una terminal con fastfetch, que es la foto clásica de una distribución.
vm 'hyprctl dispatch exec m-terminal' >/dev/null 2>&1
sleep 8
sacar "terminal" "terminal"

echo
if [ "$FALLOS" -eq 0 ]; then
    verde "Capturas en $SALIDA"
else
    rojo "$FALLOS capturas fallaron. Las que falten se quedan como estaban en la web."
fi
exit "$FALLOS"
