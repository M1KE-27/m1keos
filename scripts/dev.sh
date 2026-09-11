#!/bin/bash
# ==============================================================================
# MIKE OS - Ciclo rápido de desarrollo
#
# Aplica un cambio sobre la VM que ya está arrancada, sin reconstruir la imagen.
# El build completo (scripts/build.sh, ~6 min) queda sólo para el kernel, los
# servicios runit, el layout del rootfs y la entrega final.
#
#   ./scripts/dev.sh m-welcome     compila esa app y la relanza en la VM
#   ./scripts/dev.sh qml           recarga el panel y la barra (Quickshell)
#   ./scripts/dev.sh hypr          recarga la configuración de Hyprland
#   ./scripts/dev.sh scripts       sincroniza las herramientas mcore y desktop
#   ./scripts/dev.sh all           todo lo anterior de una pasada
#   ./scripts/dev.sh shot          captura la pantalla de la VM
#
# Requisito: la VM tiene que estar arrancada desde un build hecho con
# MIKEOS_SSH_AUTHORIZED_KEYS_FILE apuntando a la clave pública de desarrollo,
# porque el acceso es por SSH. El build de entrega no lleva ninguna clave.
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

DEV_KEY="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"
DEV_USER="${MIKEOS_DEV_USER:-mike}"
# Puertos que usan run-qemu.sh y los lanzadores de pruebas.
PORT_CANDIDATES="${MIKEOS_DEV_PORT:-} 2222 2223 2224 2225 2226 2227 2228 2229"

c_ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
c_step() { printf '\033[36m»\033[0m %s\n' "$*"; }

# ── Localizar la VM ──────────────────────────────────────────────────────────
SSH_PORT=""
find_vm() {
    for p in $PORT_CANDIDATES; do
        [ -n "$p" ] || continue
        if ssh -p "$p" -i "$DEV_KEY" \
               -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=2 -o BatchMode=yes -o LogLevel=ERROR \
               "$DEV_USER@localhost" true 2>/dev/null; then
            SSH_PORT="$p"
            return 0
        fi
    done
    return 1
}

vm() {
    ssh -p "$SSH_PORT" -i "$DEV_KEY" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR "$DEV_USER@localhost" "$@"
}

push() {
    # $1 = origen en el host, $2 = destino en la VM.
    # La transferencia va por ssh + cat, no por scp: el scp moderno habla SFTP
    # y Dropbear no trae sftp-server, así que fallaría con "No such file".
    # Se escribe primero en el home del usuario y luego se mueve con m-sudo,
    # porque /usr/bin no es escribible por mike.
    local src="$1" dst="$2" tmp
    tmp="/home/$DEV_USER/.dev-$(basename "$dst")"
    vm "cat > '$tmp'" < "$src" || return 1
    vm "m-sudo cp '$tmp' '$dst' && m-sudo chmod 755 '$dst' && rm -f '$tmp'"
}

# ── Apps en C: (fuente, salida, flags de pkg-config) ─────────────────────────
c_source_of() {
    case "$1" in
        m-welcome)    echo "$PROJECT_ROOT/build/desktop/settings/m-welcome.c|$BUILD_DIR/settings/m-welcome|gtk+-3.0" ;;
        m-settings)   echo "$PROJECT_ROOT/build/desktop/settings/m-settings.c|$BUILD_DIR/settings/m-settings|gtk+-3.0" ;;
        m-wallpapers) echo "$PROJECT_ROOT/build/desktop/settings/m-wallpapers.c|$BUILD_DIR/settings/m-wallpapers|gtk+-3.0" ;;
        m-terminal)   echo "$PROJECT_ROOT/build/mterminal/mterminal.c|$BUILD_DIR/mterminal/m-terminal|gtk+-3.0 vte-2.91" ;;
        *)            return 1 ;;
    esac
}

do_capp() {
    local app="$1" spec src out pkgs
    spec="$(c_source_of "$app")" || { c_err "App desconocida: $app"; return 1; }
    src="${spec%%|*}"; spec="${spec#*|}"
    out="${spec%%|*}"; pkgs="${spec#*|}"

    c_step "Compilando $app"
    mkdir -p "$(dirname "$out")"
    # Mismos flags que scripts/build.sh, para que lo probado sea lo que se
    # acabará entregando.
    if ! gcc -O2 -Wall $(pkg-config --cflags $pkgs) "$src" -o "$out" $(pkg-config --libs $pkgs); then
        c_err "Falló la compilación de $app"
        return 1
    fi

    c_step "Copiando a la VM"
    push "$out" "/usr/bin/$app" || { c_err "No se pudo copiar $app"; return 1; }

    # m-welcome sólo se muestra si no existe la marca de primera vez: al
    # probarlo hay que borrarla, o no se vería nada.
    if [ "$app" = "m-welcome" ]; then
        vm "rm -f ~/.config/mike/.welcomed"
    fi

    # Una sesión SSH no hereda el entorno Wayland de la sesión gráfica, así que
    # hay que reconstruirlo a mano o la app arranca y muere sin decir nada.
    c_step "Relanzando $app"
    vm "pkill -x '$app' 2>/dev/null
        sleep 0.3
        export XDG_RUNTIME_DIR=/run/user/1000
        export WAYLAND_DISPLAY=\$(ls /run/user/1000/ 2>/dev/null | grep -m1 '^wayland-[0-9]*\$')
        export HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1000/hypr/ 2>/dev/null | head -1)
        (setsid /usr/bin/$app >/dev/null 2>&1 &)
        true"
    sleep 1
    if vm "pgrep -x '$app' >/dev/null"; then
        c_ok "$app actualizado y corriendo"
    else
        c_warn "$app copiado, pero no sigue vivo (¿es una app que termina sola?)"
    fi
}

# ── QML del panel y la barra ─────────────────────────────────────────────────
do_qml() {
    c_step "Copiando QML"
    # Todos los .qml, shell.qml incluido: al añadir un componente nuevo y
    # copiar sólo dos, el panel fallaba con "X is not a type".
    "$PROJECT_ROOT/scripts/qmldir.sh"
    for _c in "$PROJECT_ROOT"/build/desktop/quickshell/*.qml; do
        push "$_c" "/etc/mikeos/desktop/$(basename "$_c")" || return 1
    done
    push "$PROJECT_ROOT/build/desktop/quickshell/qmldir" \
         "/etc/mikeos/desktop/qmldir" || return 1
    c_step "Publicando QML y reiniciando la barra"
    # Cambiar el código QML sí exige reiniciar quickshell (no recarga QML en
    # caliente). Cambiar un *ajuste* ya no: para eso está settings.json, que
    # la barra vigila sola. Este reinicio es de desarrollo, no de uso normal.
    vm 'export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1); m-apply-settings; pkill -x quickshell'
    c_ok "Panel recargado"
}

# ── Configuración de Hyprland ────────────────────────────────────────────────
do_hypr() {
    c_step "Copiando hyprland.conf"
    push "$PROJECT_ROOT/build/desktop/hyprland.conf" \
         "/etc/mikeos/desktop/hyprland.conf" || return 1
    # La sesión lee la copia del home del usuario, no la de /etc.
    vm "cat > /home/$DEV_USER/.config/mike/hyprland.conf" \
        < "$PROJECT_ROOT/build/desktop/hyprland.conf" || return 1
    c_step "Recargando Hyprland"
    vm 'export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1); hyprctl reload'
    c_ok "Hyprland recargado"
}

# ── Scripts (no se compilan: basta con copiarlos) ────────────────────────────
do_scripts() {
    local n=0 f base
    c_step "Sincronizando herramientas mcore y desktop"
    for f in "$PROJECT_ROOT"/build/mcore/*; do
        base="$(basename "$f")"
        case "$base" in *.c|m-sudo) continue ;; esac
        [ -f "$f" ] || continue
        push "$f" "/usr/bin/$base" >/dev/null 2>&1 && n=$((n + 1))
    done
    for base in m-apply-settings m-panel m-hw-profile m-launcher start-mike-desktop; do
        f="$PROJECT_ROOT/build/desktop/$base"
        [ -f "$f" ] || continue
        push "$f" "/usr/bin/$base" >/dev/null 2>&1 && n=$((n + 1))
    done
    if [ -f "$PROJECT_ROOT/build/mpm/mpm" ]; then
        push "$PROJECT_ROOT/build/mpm/mpm" "/usr/bin/mpm" >/dev/null 2>&1 && n=$((n + 1))
    fi
    # Piezas internas de MPM, en /usr/lib/mpm. El resolutor se compila aquí
    # porque es lo que más se toca al iterar sobre la instalación de paquetes
    # y esperar seis minutos de build completo por cada cambio no tiene
    # sentido.
    vm 'mkdir -p /usr/lib/mpm' >/dev/null 2>&1
    if [ -f "$PROJECT_ROOT/build/mpm/sync" ]; then
        push "$PROJECT_ROOT/build/mpm/sync" "/usr/lib/mpm/sync" >/dev/null 2>&1 && n=$((n + 1))
    fi
    if [ -f "$PROJECT_ROOT/build/mpm/resolver.c" ]; then
        if gcc -O2 -static -Wall "$PROJECT_ROOT/build/mpm/resolver.c" \
               -o "$PROJECT_ROOT/build/mpm/bin-resolver" 2>/dev/null; then
            push "$PROJECT_ROOT/build/mpm/bin-resolver" "/usr/lib/mpm/resolver" >/dev/null 2>&1 && n=$((n + 1))
        else
            c_err "el resolutor de MPM no compila"
        fi
    fi
    c_ok "$n scripts sincronizados"
}

# ── Captura de pantalla de la VM ─────────────────────────────────────────────
do_shot() {
    local out="${1:-/tmp/mikeos-dev-shot.png}"
    if ! command -v grim >/dev/null 2>&1; then
        c_err "grim no está instalado en el host"
        return 1
    fi
    grim "$out" && c_ok "Captura en $out"
}

usage() {
    sed -n '5,18p' "$0" | sed 's/^# \{0,1\}//'
}

# ── Punto de entrada ─────────────────────────────────────────────────────────
TARGET="${1:-}"
[ -n "$TARGET" ] || { usage; exit 1; }

case "$TARGET" in
    -h|--help|help) usage; exit 0 ;;
    shot) do_shot "${2:-}"; exit $? ;;
esac

if [ ! -f "$DEV_KEY" ]; then
    c_err "No existe la clave de desarrollo: $DEV_KEY"
    echo "   Genera una y reconstruye con ella:" >&2
    echo "     ssh-keygen -t ed25519 -N '' -f $DEV_KEY" >&2
    echo "     MIKEOS_SSH_AUTHORIZED_KEYS_FILE=$DEV_KEY.pub ./scripts/build.sh" >&2
    exit 1
fi

c_step "Buscando la VM"
if ! find_vm; then
    c_err "No hay ninguna VM de MIKE OS accesible por SSH."
    echo "   Arráncala con: ./scripts/run-qemu.sh --gui --desktop" >&2
    echo "   y comprueba que el build lleva la clave de desarrollo." >&2
    exit 1
fi
c_ok "VM encontrada en el puerto $SSH_PORT"

rc=0
case "$TARGET" in
    m-welcome|m-settings|m-wallpapers|m-terminal) do_capp "$TARGET" || rc=1 ;;
    qml)     do_qml || rc=1 ;;
    hypr)    do_hypr || rc=1 ;;
    scripts) do_scripts || rc=1 ;;
    all)
        do_scripts || rc=1
        do_qml     || rc=1
        do_hypr    || rc=1
        ;;
    *)
        c_err "Objetivo desconocido: $TARGET"
        usage
        exit 1
        ;;
esac

exit $rc
