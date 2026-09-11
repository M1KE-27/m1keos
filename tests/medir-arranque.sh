#!/bin/bash
# ==============================================================================
# medir-arranque.sh - cuánto tarda MIKE OS en estar utilizable.
#
# Mide dos momentos distintos, porque son dos cosas distintas:
#   SSH        el sistema responde: kernel, runit, red y servicios en pie
#   escritorio Hyprland y la barra funcionando, que es cuando alguien lo usa
#
# Sirve sobre todo para comparar con y sin KVM: la diferencia entre emular cada
# instrucción y ejecutarla en el procesador de verdad no es un detalle, es la
# diferencia entre trabajar y esperar.
#
#   ./tests/medir-arranque.sh
#   ./tests/medir-arranque.sh --sin-kvm     fuerza emulación, para comparar
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAVE="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"
PUERTO="${MIKEOS_DEV_PORT:-2222}"
REGISTRO="${TMPDIR:-/tmp}/mikeos-medir.log"

EXTRA=()
ETIQUETA="con KVM"
if [ "${1:-}" = "--sin-kvm" ]; then
    EXTRA=(--no-kvm)
    ETIQUETA="sin KVM (emulación)"
fi

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }

vm() {
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 \
        -o BatchMode=yes -o LogLevel=ERROR mike@localhost "$@" 2>/dev/null
}

pkill -9 -f qemu-system-x86_64 2>/dev/null
sleep 2

echo "Midiendo el arranque $ETIQUETA..."
INICIO=$(date +%s)
"$RAIZ/scripts/run-qemu.sh" --gui --desktop --ssh-port "$PUERTO" "${EXTRA[@]}" \
    > "$REGISTRO" 2>&1 < /dev/null &
QPID=$!

# Hasta que responde por SSH: el sistema está en pie.
T_SSH=""
for _ in $(seq 1 600); do
    if vm true >/dev/null 2>&1; then T_SSH=$(( $(date +%s) - INICIO )); break; fi
    sleep 1
done
if [ -z "$T_SSH" ]; then
    echo "No llegó a responder. Registro en $REGISTRO"
    kill -9 "$QPID" 2>/dev/null
    exit 1
fi

# Hasta que la barra está viva: el escritorio es utilizable.
T_ESC=""
for _ in $(seq 1 600); do
    if vm 'pgrep -x quickshell >/dev/null'; then T_ESC=$(( $(date +%s) - INICIO )); break; fi
    sleep 1
done

echo
verde "  $ETIQUETA"
printf '    %-28s %ss\n' "responde por SSH" "$T_SSH"
[ -n "$T_ESC" ] && printf '    %-28s %ss\n' "escritorio utilizable" "$T_ESC"

# Y lo que tarda el propio kernel según él mismo, que no depende de la máquina
# anfitriona tanto como el resto.
ARRANQUE="$(vm 'cut -d" " -f1 /proc/uptime' 2>/dev/null)"
[ -n "$ARRANQUE" ] && gris "    (el sistema cree llevar ${ARRANQUE}s encendido)"

kill -9 "$QPID" 2>/dev/null
