#!/bin/bash
# Regenera build/desktop/quickshell/qmldir a partir de los componentes que
# haya en la carpeta.
#
# Hace falta porque el singleton Paleta obliga a tener un qmldir, y en cuanto
# hay uno, QML deja de descubrir los componentes de la carpeta solo: los que
# no estén declarados dejan de existir ("Dato is not a type"). Generarlo en
# cada build evita que añadir un componente nuevo rompa el escritorio.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../build/desktop/quickshell" && pwd)"
{
    echo "# Generado por scripts/qmldir.sh -- no editar a mano."
    echo "# Con un qmldir presente, QML deja de descubrir los componentes de la"
    echo "# carpeta por su cuenta: hay que declararlos todos o dejan de existir."
    echo
    for f in "$DIR"/*.qml; do
        tipo="$(basename "$f" .qml)"
        [ "$tipo" = "shell" ] && continue
        if [ "$tipo" = "Paleta" ]; then
            echo "singleton $tipo 1.0 $tipo.qml"
        else
            echo "$tipo 1.0 $tipo.qml"
        fi
    done
} > "$DIR/qmldir"
