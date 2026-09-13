#!/bin/bash
# ==============================================================================
# barra-posiciones.sh - la barra sobrevive a moverla de sitio una y otra vez.
#
# Existe por un fallo concreto: al mandar la barra a un lateral, volvía rota, y
# al devolverla arriba SEGUÍA rota. No era un problema de dibujado sino de
# estado: las zonas cambiaban de anclaje con seis enlaces que QML reevaluaba
# uno a uno, y en el camino quedaban con "top" y "verticalCenter" puestos a la
# vez. Qt lee esa pareja como un estiramiento, fija la altura a mano, y desde
# ese momento el elemento deja de medirse por su tamaño natural PARA SIEMPRE.
#
# Por eso la prueba no mira si la barra "se ve bien" en cada posición: mira si,
# después de dar la vuelta entera, la barra vuelve a estar EXACTAMENTE como al
# principio. Eso es lo que se rompía, y una captura suelta no lo habría pillado.
#
#   ./tests/barra-posiciones.sh
#
# Necesita la clave de desarrollo dentro de la imagen:
#   MIKEOS_SSH_AUTHORIZED_KEYS_FILE=~/.ssh/mikeos_dev.pub ./scripts/build.sh
#   ./scripts/crear-iso.sh
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRABAJO="${MIKEOS_TEST_DIR:-${TMPDIR:-/tmp}/mikeos-barra-pos}"
ISO="$RAIZ/iso/mikeos.iso"
CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd
CLAVE="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"
PUERTO="${MIKEOS_BARRA_PORT:-2256}"
ANCHO=1920
ALTO=1080
# Franja donde vive la barra cuando está arriba. Con 48 px de alto por defecto
# sobra de largo, y de paso no entra el borde de la ventana de bienvenida.
FRANJA=48

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }

vm() {
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ConnectTimeout=5 -o BatchMode=yes mike@localhost \
        "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; $*" 2>/dev/null
}

[ -f "$ISO" ] || { rojo "No hay ISO. Ejecuta ./scripts/crear-iso.sh"; exit 1; }
[ -f "$CODE" ] || { rojo "Falta OVMF ($CODE). Instala edk2-ovmf."; exit 1; }
[ -f "$CLAVE" ] || { rojo "Falta la clave de desarrollo ($CLAVE)."; exit 1; }
command -v python3 >/dev/null || { rojo "Hace falta python3."; exit 1; }
python3 -c "import PIL" 2>/dev/null || { rojo "Hace falta python-pillow."; exit 1; }

rm -rf "$TRABAJO"; mkdir -p "$TRABAJO"
cp "$VARS" "$TRABAJO/vars.fd"; chmod u+w "$TRABAJO/vars.fd"

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=(-enable-kvm -cpu host)
else
    # shellcheck disable=SC2054  # "tcg,thread=multi" es un solo argumento de QEMU
    ACCEL=(-accel tcg,thread=multi -cpu max)
fi

paso "Arrancando la ISO"
# usb-tablet no es opcional aunque esta prueba no use el ratón: sin un puntero
# absoluto, QMP no puede colocar el cursor y la barra recibe eventos de hover
# en sitios que no son, lo que ensucia las capturas.
qemu-system-x86_64 "${ACCEL[@]}" -m 4096 -smp 4 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$TRABAJO/vars.fd" \
    -drive "format=raw,file=$ISO" \
    -netdev "user,id=n0,hostfwd=tcp::$PUERTO-:22" -device virtio-net-pci,netdev=n0 \
    -device virtio-vga -display none -device qemu-xhci -device usb-tablet \
    -qmp "unix:$TRABAJO/qmp.sock,server=on,wait=off" \
    -serial "file:$TRABAJO/serie.log" -no-reboot \
    > "$TRABAJO/qemu.log" 2>&1 &
QPID=$!
# shellcheck disable=SC2064
trap "kill -9 $QPID 2>/dev/null" EXIT

printf "Esperando al escritorio"
LISTO=0
for _ in $(seq 1 90); do
    if vm 'pgrep -x Hyprland >/dev/null && pgrep -x quickshell >/dev/null'; then
        LISTO=1; break
    fi
    printf "."
    sleep 4
done
echo
[ "$LISTO" -eq 1 ] || { rojo "El escritorio no llegó a levantarse."; exit 1; }
verde "Escritorio en pie."

# La ventana de bienvenida tapa media pantalla y cambia entre capturas. Fuera.
vm 'pkill -f m-welcome' >/dev/null 2>&1
sleep 2

foto() {
    python3 - "$TRABAJO/qmp.sock" "$1" <<'PY'
import json, socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.settimeout(6)
s.recv(65536)
def q(c):
    s.sendall((json.dumps(c) + "\n").encode()); time.sleep(0.25)
    try: return s.recv(65536)
    except Exception: return b""
q({"execute": "qmp_capabilities"})
q({"execute": "screendump", "arguments": {"filename": sys.argv[2]}})
time.sleep(1.2)
PY
}

paso "Recorriendo las cuatro posiciones y volviendo al principio"
for pos in top right bottom left top; do
    vm "m-apply-settings set bar_position=$pos" >/dev/null 2>&1
    sleep 4
    foto "$TRABAJO/$pos-$RANDOM.ppm"
    gris "  $pos"
done

# La primera y la última captura son las dos con la barra arriba. Si el ciclo
# no dejó secuelas, la barra tiene que ocupar exactamente lo mismo en las dos.
paso "Comparando la barra de antes con la de después"
python3 - "$TRABAJO" "$ANCHO" "$FRANJA" <<'PY'
import glob, os, sys
from PIL import Image

trabajo, ancho, franja = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
tops = sorted(glob.glob(os.path.join(trabajo, "top-*.ppm")), key=os.path.getmtime)
if len(tops) < 2:
    print("FALLO: faltan capturas de la posición de arriba.")
    sys.exit(1)

def extremos(ruta):
    """Primera y última columna con algo pintado en la franja de la barra."""
    g = Image.open(ruta).convert("L").crop((0, 0, ancho, franja))
    px = g.load()
    cols = [x for x in range(g.width)
            if max(px[x, y] for y in range(g.height)) > 90]
    return (cols[0], cols[-1]) if cols else None

a, b = extremos(tops[0]), extremos(tops[-1])
print(f"  antes del ciclo:   {a}")
print(f"  después del ciclo: {b}")
if a is None or b is None:
    print("FALLO: la barra no pinta nada en alguna de las dos.")
    sys.exit(1)
# Un píxel de margen: el reloj y los medidores cambian de ancho solos.
if abs(a[0] - b[0]) > 1 or abs(a[1] - b[1]) > 1:
    print("FALLO: la barra no ocupa lo mismo que antes del ciclo.")
    print("  Es el fallo de los anclajes: alguna zona se quedó con el tamaño")
    print("  congelado y ya no se mide por su contenido.")
    sys.exit(1)
print("OK")
PY
RC=$?

echo
if [ "$RC" -eq 0 ]; then
    verde "La barra vuelve intacta después de dar la vuelta entera."
else
    rojo "La barra no vuelve a su sitio: hay estado que sobrevive al cambio."
    gris "  Capturas en $TRABAJO"
fi
exit "$RC"
