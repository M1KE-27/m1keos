#!/bin/bash
# ==============================================================================
# actualizar-kernel.sh - pasar MIKE OS a la última estable de kernel.org.
#
# Qué hace, en orden, y se planta en cuanto algo no cuadra:
#   1. Pregunta a kernel.org cuál es la última estable (releases.json).
#   2. Trae SÓLO esa etiqueta al árbol de kernel/ (unos megas, no 4 GB).
#   3. Aplica los parches de build/kernel-patches/ sobre ella, sin escribir
#      nada en build.sh todavía, y mira que no dejen valores repetidos
#      (scripts/choques-kernel.py).
#   4. Comprueba que las ~400 opciones del fragmento .config siguen existiendo
#      en esa versión (tests/kernel-config.sh): entre versiones se renombran y
#      desaparecen en silencio.
#   5. Sólo si todo pasa, escribe la etiqueta y el commit en build.sh.
#
# Después hay que construir y probar como siempre: ./scripts/build.sh y
# ./tests/humo.sh. Este script no compila nada.
#
#   ./scripts/actualizar-kernel.sh            la última estable de hoy
#   ./scripts/actualizar-kernel.sh v7.2.9     una etiqueta concreta
#   ./scripts/actualizar-kernel.sh --ver      sólo dice cuál hay, sin tocar
#
# Antes iba a la rama "master" de torvalds (desarrollo, sin publicar) y
# buscaba los parches en "kernel-parches/", que no existe: no los aplicaba.
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$RAIZ/kernel"
BUILD="$RAIZ/scripts/build.sh"
REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }

ACTUAL_TAG="$(sed -n 's/^KERNEL_TAG="\(.*\)"/\1/p' "$BUILD")"

case "${1:-}" in
    ""|--ver)
        paso "Preguntando a kernel.org"
        TAG="v$(curl -fsSL https://www.kernel.org/releases.json \
                | python3 -c 'import json,sys; print(json.load(sys.stdin)["latest_stable"]["version"])')" \
            || { rojo "No se pudo leer kernel.org."; exit 1; }
        echo "  última estable: $TAG   ·   la de MIKE OS: ${ACTUAL_TAG:-?}"
        [ "${1:-}" = "--ver" ] && exit 0
        ;;
    v*) TAG="$1" ;;
    *)  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

if [ "$TAG" = "$ACTUAL_TAG" ]; then
    verde "MIKE OS ya está en $TAG."
    exit 0
fi

[ -d "$KERNEL/.git" ] || { rojo "No hay árbol en $KERNEL: ./scripts/build.sh lo clona."; exit 1; }

paso "Trayendo $TAG"
git -C "$KERNEL" fetch -q --no-tags "$REPO" "refs/tags/$TAG:refs/tags/$TAG" \
    || { rojo "kernel.org no tiene la etiqueta $TAG."; exit 1; }
COMMIT="$(git -C "$KERNEL" rev-parse "$TAG^{commit}")"
echo "  $TAG = $COMMIT"

paso "Aplicando los parches de build/kernel-patches/ sobre $TAG"
git -C "$KERNEL" checkout -q -- . && git -C "$KERNEL" clean -qfd
git -C "$KERNEL" checkout -q --detach "$COMMIT" || exit 1
MAL=0
for p in "$RAIZ"/build/kernel-patches/*.patch; do
    if git -C "$KERNEL" apply "$p" 2>/dev/null; then
        echo "  ✓ $(basename "$p")"
    else
        rojo "  ✗ $(basename "$p") no entra: hay que adaptarlo a $TAG."
        MAL=1
    fi
done
[ "$MAL" = 0 ] || exit 1
python3 "$RAIZ/scripts/choques-kernel.py" "$KERNEL" "$COMMIT" || { rojo "Los parches chocan (arriba)."; exit 1; }
echo "  sin valores repetidos"

paso "Comprobando las opciones del fragmento en $TAG"
"$RAIZ/tests/kernel-config.sh" || { rojo "Hay opciones que $TAG ya no tiene (arriba)."; exit 1; }

paso "Fijándolo en build.sh"
sed -i "s|^KERNEL_TAG=\".*\"|KERNEL_TAG=\"$TAG\"|; s|^KERNEL_COMMIT=\".*\"|KERNEL_COMMIT=\"$COMMIT\"|" "$BUILD"
verde "Listo: ${ACTUAL_TAG:-?} → $TAG. Ahora ./scripts/build.sh y ./tests/humo.sh."
