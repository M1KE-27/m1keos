#!/bin/bash
# Recorre el Centro de Control pulsando cada botón como lo haría un dedo.
#
# Por qué existe
# --------------
# Hasta ahora las pruebas de clic usaban el puntero absoluto de QEMU: saltaba a
# una coordenada, pulsaba y soltaba sin moverse ni un píxel. Un dedo en un
# touchpad no hace eso, y esa diferencia bastaba para que el banco de pruebas
# diera por buenos botones que en un portátil no respondían. Literalmente:
# "todo muy bonito en QEMU y en hardware real nada".
#
# Esto usa tests/clic-real.py, que pulsa y ARRASTRA unos píxeles antes de
# soltar, que es lo que hace un dedo. Si un control vuelve a quedarse con la
# política de toque por defecto de Qt, esta prueba lo caza.
#
# Comprobado que sirve: quitando el "gesturePolicy" del shell.qml de una
# máquina en marcha, estas mismas pulsaciones dejan de abrir el panel. Una
# prueba que no puede fallar no es una prueba.
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUERTO="${MIKEOS_DEV_PORT:-2223}"
QMP="${MIKEOS_QMP_SOCKET:-/tmp/mikeos-raton-qmp.sock}"
CLAVE="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"

verde() { printf '\033[32m%s\033[0m' "$*"; }
rojo()  { printf '\033[31m%s\033[0m' "$*"; }
gris()  { printf '\033[90m%s\033[0m' "$*"; }

vm() {
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ConnectTimeout=4 -o BatchMode=yes mike@localhost \
        "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1; $*" 2>/dev/null
}

clic() {
    MIKEOS_QMP_SOCKET="$QMP" python3 "$RAIZ/tests/clic-real.py" \
        "$1" "$2" --pantalla "$ANCHO" "$ALTO" >/dev/null 2>&1
    sleep 1.5
}

# La resolución la decide m-hw-profile, así que se pregunta en vez de suponer.
ancho_alto() {
    vm 'export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr 2>/dev/null | head -1); hyprctl monitors' \
        | awk '/^\t[0-9]+x[0-9]+@/ { split($1, a, "@"); split(a[1], b, "x"); print b[1], b[2]; exit }'
}

echo "== Pulsaciones con ratón relativo (como un touchpad) =="

for p in $(pgrep -f "^qemu-system-x86_64" 2>/dev/null); do kill "$p" 2>/dev/null; done
sleep 2
rm -f "$QMP"

MIKEOS_QMP_SOCKET="$QMP" \
    setsid "$RAIZ/scripts/run-qemu.sh" --gui --desktop --ssh-port "$PUERTO" \
    > /tmp/mikeos-raton.log 2>&1 < /dev/null &

printf 'Esperando al escritorio'
LISTO=0
for _ in $(seq 1 60); do
    if vm 'pgrep -x quickshell >/dev/null'; then LISTO=1; break; fi
    printf '.'
    sleep 5
done
echo
[ "$LISTO" = 1 ] || { echo "$(rojo '✗') el escritorio no llegó a levantarse"; exit 1; }

read -r ANCHO ALTO <<< "$(ancho_alto)"
[ -n "${ANCHO:-}" ] || { echo "$(rojo '✗') no se pudo leer la resolución"; exit 1; }
echo "$(gris "pantalla: ${ANCHO}x${ALTO}")"

PASAN=0; FALLAN=0

# Se le PREGUNTA a la barra, no se adivina mirando píxeles.
#
# La primera versión comparaba capturas de pantalla, como hace tests/humo.sh.
# No vale: la barra lleva un reloj, así que dos capturas separadas por un
# segundo salen siempre distintas y la comprobación daba que sí pasara lo que
# pasara. Recortar la zona del reloj tampoco bastó, porque hay más cosas que
# se mueven. Por eso shell.qml expone ahora "estado".
# La identificación de la instancia de quickshell.
#
# "quickshell ipc call ..." a secas no vale desde fuera de la sesión: busca una
# configuración "default" y una pantalla Wayland que por SSH no existen. Hay
# que nombrarle la instancia.
INSTANCIA=""
estado() {
    if [ -z "$INSTANCIA" ]; then
        INSTANCIA="$(vm 'quickshell list --all' | awk '/^Instance /{gsub(":","",$2); print $2; exit}')"
        [ -n "$INSTANCIA" ] || return 1
    fi
    vm "quickshell ipc -i $INSTANCIA call ajustes estado" | tr -d "\r"
}

comprobar() {  # comprobar <nombre> <lo que tiene que decir el estado>
    printf '  %-44s' "$1"
    _e="$(estado)"
    case "$_e" in
        $2) echo "$(verde ✓)  $(gris "$_e")"; PASAN=$((PASAN+1)); return 0 ;;
        *)  echo "$(rojo ✗)  $(gris "dijo: ${_e:-nada}")"; FALLAN=$((FALLAN+1)); return 1 ;;
    esac
}

printf '  %-44s' "la barra contesta a las preguntas"
case "$(estado)" in
    abierto*|cerrado*) echo "$(verde ✓)"; PASAN=$((PASAN+1)) ;;
    *) echo "$(rojo ✗)  $(gris 'sin respuesta por IPC')"; FALLAN=$((FALLAN+1)) ;;
esac

# El botón de ajustes de la barra, pegado al borde derecho. Con arrastre.
clic $((ANCHO - 32)) 23
comprobar "el Centro de Control abre con arrastre" "abierto*" || true

# Y ahora TODOS los apartados del menú lateral.
#
# No se clavan las coordenadas de cada uno: se recorre la columna de arriba
# abajo y se apunta qué apartado queda seleccionado en cada altura. Probé a
# calcularlas (la ventana mide 940x640 y va centrada) y es frágil: un paso de
# 35 píxeles acertaba siete de nueve y uno de 36 fallaba ocho, porque la
# resolución y los márgenes cambian de un equipo a otro. Lo que importa no es
# dónde está cada fila, sino que LAS NUEVE se puedan alcanzar pulsando con
# arrastre.
VENT_X=$(( (ANCHO - 940) / 2 ))
VENT_Y=$(( 48 + (ALTO - 48 - 640) / 2 ))
X_MENU=$(( VENT_X + 80 ))

ALCANZADOS=""
Y=$(( VENT_Y + 100 ))
FIN=$(( VENT_Y + 410 ))
while [ "$Y" -le "$FIN" ]; do
    clic "$X_MENU" "$Y"
    _e="$(estado)"
    case "$_e" in
        abierto\ *)
            _sec="${_e#abierto }"
            case " $ALCANZADOS " in
                *" $_sec "*) : ;;
                *) ALCANZADOS="$ALCANZADOS $_sec" ;;
            esac
            ;;
        *)
            # Si el panel se cierra recorriendo el menú, es justo el fallo que
            # esta prueba busca: un arrastre no debe cerrar nada.
            printf '  %-44s' "el menú lateral no cierra el panel"
            echo "$(rojo ✗)  $(gris "se cerró en y=$Y")"
            FALLAN=$((FALLAN + 1))
            break
            ;;
    esac
    Y=$(( Y + 12 ))
done

# Los apartados que DEBE haber. "interfaz", "servicios" y "avanzado" se
# retiraron del menú porque no tenían dentro ni un control: eran un título y
# una frase diciendo que llegarían más adelante. Si vuelven, tendrán que volver
# también a esta lista, con algo dentro que probar.
for SEC in vistazo sistema energia drivers barra escritorio bloqueo acercade; do
    printf '  %-44s' "el apartado «$SEC» se puede abrir"
    case " $ALCANZADOS " in
        *" $SEC "*) echo "$(verde ✓)"; PASAN=$((PASAN + 1)) ;;
        *) echo "$(rojo ✗)  $(gris 'no se alcanzó con ninguna pulsación')"; FALLAN=$((FALLAN + 1)) ;;
    esac
done

# Cerrar pulsando fuera, que es lo que espera cualquiera de un diálogo.
clic $(( ANCHO / 2 )) $(( ALTO - 60 ))
comprobar "se cierra al pulsar fuera" "cerrado*" || true

echo
if [ "$FALLAN" = 0 ]; then
    echo " $(verde 'Todo pasa') — $PASAN comprobaciones con ratón relativo."
else
    echo " $(rojo "$FALLAN fallo(s)") de $((PASAN+FALLAN))."
fi
for p in $(pgrep -f "^qemu-system-x86_64" 2>/dev/null); do kill "$p" 2>/dev/null; done
[ "$FALLAN" = 0 ]
