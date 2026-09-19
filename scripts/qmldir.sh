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
        # Los archivos que empiezan en minúscula son programas enteros
        # (shell.qml, bloqueo.qml), no componentes. Un tipo QML tiene que
        # empezar por mayúscula, así que declararlos aquí no sólo sobra:
        # invalida el qmldir y con él TODOS los componentes de la carpeta.
        case "$tipo" in
            [a-z]*) continue ;;
        esac
        # Se mira el archivo en vez de llevar la lista escrita aquí. Cuando
        # sólo había un singleton (Paleta) el nombre estaba puesto a mano, y
        # al añadir el segundo (Idioma) salía declarado como componente
        # normal: QML lo instancia entonces por cada uso, cada copia lanza su
        # propio "m-idioma", y el valor deja de ser compartido --- que es lo
        # único que un singleton tiene que garantizar.
        if head -1 "$f" | grep -q "^pragma Singleton"; then
            echo "singleton $tipo 1.0 $tipo.qml"
        else
            echo "$tipo 1.0 $tipo.qml"
        fi
    done
} > "$DIR/qmldir"
