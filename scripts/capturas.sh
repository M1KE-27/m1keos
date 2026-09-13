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
# Requiere una VM arrancada con escritorio:  ./tests/humo.sh --dejar
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAVE="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"
PUERTO="${MIKEOS_DEV_PORT:-2222}"
SALIDA="${1:-$RAIZ/build/web/capturas}"

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }

vm() {
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 \
        mike@localhost \
        "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; \
         export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1; $*" 2>/dev/null
}

sacar() {  # sacar <nombre> <descripción>
    vm "grim /tmp/cap.png >/dev/null 2>&1"
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        mike@localhost 'cat /tmp/cap.png' > "$SALIDA/$1.png" 2>/dev/null
    if [ -s "$SALIDA/$1.png" ]; then
        verde "  $1.png  ($2)"
    else
        printf '  \033[31m%s falló\033[0m\n' "$1"
    fi
}

clic() { python3 "$RAIZ/tests/clic.py" "$1" "$2" >/dev/null 2>&1; sleep 3; }

vm true >/dev/null 2>&1 || { echo "No hay VM en el puerto $PUERTO."; exit 1; }
mkdir -p "$SALIDA"

paso "Sacando capturas"

# 1. La bienvenida, que es lo primero que ve alguien.
if [ -n "$(vm 'pgrep m-welcome')" ]; then
    sacar "bienvenida" "pantalla de inicio"
    # Cerrarla para las siguientes: el botón "Empezar" está abajo a la derecha
    # de la ventana flotante de 880x580 centrada en 1920x1080.
    clic 1348 774
fi

# 2. El escritorio con la barra.
sacar "escritorio" "escritorio y barra"

# 3. El Centro de Control abierto.
clic 1888 23
sacar "centro-de-control" "Centro de Control"
clic 570 457            # apartado Escritorio, que enseña más controles
sacar "ajustes-escritorio" "ajustes del escritorio"
clic 960 1000           # cerrar

# 4. Una terminal con fastfetch, que es la foto clásica de una distribución.
vm 'hyprctl dispatch exec m-terminal' >/dev/null 2>&1
sleep 8
sacar "terminal" "terminal"

echo
verde "Capturas en $SALIDA"
