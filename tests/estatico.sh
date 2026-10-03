#!/bin/bash
# Todo lo que se puede comprobar SIN arrancar una máquina, de una vez.
#
# Cada una de estas pruebas existe porque algo se rompió en silencio: compilaba,
# arrancaba en QEMU, y fallaba en un portátil concreto o al cabo de semanas.
# Tarda menos de un minuto, así que se pasa antes de cada build.
#
#   ./tests/estatico.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

OK=0; MAL=0; FALLOS=()
seccion() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bien()    { printf '  \033[32m✓\033[0m %s\n' "$1"; OK=$((OK+1)); }
mal()     { printf '  \033[31m✗\033[0m %s\n' "$1"; MAL=$((MAL+1)); FALLOS+=("$1"); }
correr()  { # correr <nombre> <orden...>
    local n="$1"; shift
    local out; if out="$("$@" 2>&1)"; then bien "$n"; else mal "$n"; printf '%s\n' "$out" | tail -15 | sed 's/^/      /'; fi
}

seccion "Sintaxis de los scripts del sistema"
_malos=""
while IFS= read -r f; do
    head -1 "$f" | grep -qE '^#!.*(ba)?sh' || continue
    if head -1 "$f" | grep -q bash; then bash -n "$f" 2>/dev/null || _malos="$_malos $f"
    else sh -n "$f" 2>/dev/null || _malos="$_malos $f"; fi
done < <(find build/mcore build/desktop build/etc-tree build/mpm scripts tests -type f \
              -not -path '*/repo_pkgs/*' -not -name '*.c' -not -name '*.qml' 2>/dev/null)
[ -z "$_malos" ] && bien "todos los scripts de shell se leen" || mal "scripts con errores de sintaxis:$_malos"

seccion "Menús de arranque"
for f in build/grub/grub.cfg.iso build/grub/grub.cfg.arranque; do
    if command -v grub-script-check >/dev/null; then correr "$f" grub-script-check "$f"
    else printf '  · %s (sin grub-script-check en este equipo)\n' "$f"; fi
done

correr "el instalador encuentra a Windows para el menú" ./tests/menu-dualboot.sh

seccion "Kernel"
if [ -f kernel/Makefile ]; then
    correr "el fragmento .config acaba entero en el kernel" ./tests/kernel-config.sh
    _c="$(sed -n 's/^KERNEL_COMMIT="\(.*\)"/\1/p' scripts/build.sh)"
    if git -C kernel cat-file -e "$_c^{commit}" 2>/dev/null; then
        correr "los parches no dejan valores repetidos" python3 scripts/choques-kernel.py kernel "$_c"
    fi
else
    printf '  · sin árbol del kernel todavía\n'
fi

seccion "Firmware"
if [ -f kernel/modules.builtin.modinfo ] && [ -d rootfs/lib/firmware ]; then
    correr "ningún driver se queda sin firmware" ./tests/firmware.sh
else
    printf '  · hace falta una imagen construida\n'
fi

seccion "Traducciones e IPC"
correr "escritorio, bienvenida e informe en los dos idiomas" ./tests/traducciones.sh

printf '\n\033[1m%d de %d\033[0m\n' "$OK" "$((OK+MAL))"
[ "$MAL" -eq 0 ]
