#!/bin/bash
# ==============================================================================
# publicar-release.sh - sube la ISO a GitHub como release.
#
# La ISO no se sirve desde casa. Medido: la línea de subida da unos 780 KB/s,
# o sea casi cuatro minutos por descarga y una sola persona a la vez; dos o
# tres simultáneas dejan la casa sin internet. GitHub se come ese ancho de
# banda gratis, y la línea de casa se queda para el repositorio de paquetes,
# que son archivos pequeños.
#
# Antes de publicar comprueba que la ISO corresponde al código que hay: una
# release que no coincide con su etiqueta es peor que no tener release.
#
#   ./scripts/publicar-release.sh v0.2.0
#   ./scripts/publicar-release.sh v0.2.0 --borrador   para revisarla antes
#
# Las etiquetas que llevan -alpha, -beta o -rc se marcan solas como versión de
# prueba en GitHub.
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="$RAIZ/iso/mikeos.iso"
REPO="${MIKEOS_REPO_GITHUB:-M1KE-27/m1keos}"

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }
err()   { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

ETIQUETA="${1:-}"
[ -n "$ETIQUETA" ] || { err "falta la etiqueta. Ej: ./scripts/publicar-release.sh v0.2.0"; exit 1; }
BORRADOR=""
PRUEBA=""
for _a in "$@"; do
    case "$_a" in
        --borrador) BORRADOR="--draft" ;;
        # Una alpha tiene que ir marcada COMO alpha en GitHub, no sólo en el
        # nombre. Sin esto, "la última versión" que ofrece la API --- y que usa
        # generar-web.sh para montar el enlace de descarga --- sería una alpha
        # presentada como si fuera estable.
        --alpha|--prueba) PRUEBA="--prerelease" ;;
    esac
done
# Y si la etiqueta ya lo dice, no hace falta repetirlo en la línea de órdenes:
# olvidarse de la opción no debería poder convertir una alpha en estable.
case "$ETIQUETA" in
    *-alpha*|*-beta*|*-rc*) PRUEBA="--prerelease" ;;
esac

command -v gh >/dev/null 2>&1 || { err "falta gh (github-cli)"; exit 1; }
gh auth status >/dev/null 2>&1 || { err "gh no está autenticado. Ejecuta: gh auth login"; exit 1; }
[ -f "$ISO" ] || { err "no hay ISO. Ejecuta ./scripts/crear-iso.sh"; exit 1; }

# --- Que la ISO sea de este código -------------------------------------------
# Una ISO más vieja que el último commit es una release que promete un código
# que no lleva dentro.
paso "Comprobando que la ISO corresponde al código"
# No vale comparar con el último commit a secas: un commit que sólo toca la
# documentación o este mismo script no cambia nada de lo que va DENTRO de la
# imagen, y exigir reconstruirla por eso es ruido que acaba enseñando a
# ignorar el aviso.
#
# Se compara contra el ARCHIVO más reciente de los que entran en la imagen, no
# contra la fecha del último commit.
#
# Usar la fecha del commit no puede funcionar: primero se construye la imagen y
# después se hace el commit, así que el commit es SIEMPRE más nuevo que la ISO
# y el aviso saltaba siempre. Un aviso que salta siempre no avisa de nada:
# enseña a saltárselo, que es justo lo contrario de para lo que está.
#
# La pregunta de verdad es si algún archivo que va DENTRO de la imagen se ha
# tocado después de construirla. Eso lo contesta la fecha de los archivos.
#
# Se excluye lo que GENERA el propio build (el firmware que empotra en el
# kernel, el qmldir de quickshell, los paquetes): esos archivos son más nuevos
# que la ISO por construcción, no porque nadie los haya editado, y avisar por
# ellos es avisar siempre.
RUTAS_DE_LA_IMAGEN="build .config scripts/build.sh scripts/build-repo.sh scripts/crear-iso.sh"
FECHA_ISO=$(stat -c %Y "$ISO")
# shellcheck disable=SC2086
MAS_NUEVO=$(find $RUTAS_DE_LA_IMAGEN -newer "$ISO" -type f \
                 -not -path "build/firmware-kernel/*" \
                 -not -name "qmldir" \
                 -not -path "build/web/*" \
                 -not -path "build/cursor/*" \
                 -not -path "build/repo/*" -not -path "build/repo_pkgs/*" \
                 -not -path "build/repo_mpm_tmp/*" \
                 -not -path "*/busybox-*" -not -path "*/dropbear-*" \
                 -not -path "*/runit-*" 2>/dev/null | head -3)
if [ -n "$MAS_NUEVO" ]; then
    err "hay archivos de la imagen más nuevos que la ISO."
    gris "  ISO de $(date -d "@$FECHA_ISO" '+%F %T'), y después se tocó:"
    printf '%s\n' "$MAS_NUEVO" | sed 's/^/    /' >&2
    gris "  Reconstruye:  ./scripts/build.sh && ./scripts/crear-iso.sh"
    exit 1
fi
if [ -n "$(git -C "$RAIZ" status --porcelain)" ]; then
    err "hay cambios sin guardar. Una release tiene que salir de un commit."
    git -C "$RAIZ" status --short | head -5 >&2
    exit 1
fi
verde "  la ISO lleva el código de ahora y no hay cambios sueltos"

# --- Datos ------------------------------------------------------------------
TAM=$(du -h "$ISO" | cut -f1)
SHA=$(cut -d' ' -f1 "$ISO.sha256" 2>/dev/null || sha256sum "$ISO" | cut -d' ' -f1)
KVER=$(cat "$RAIZ/kernel/include/config/kernel.release" 2>/dev/null || echo "?")
COMMIT=$(git -C "$RAIZ" rev-parse --short HEAD)
gris "  $TAM · kernel $KVER · commit $COMMIT"

# --- Notas ------------------------------------------------------------------
NOTAS="$(mktemp)"
trap 'rm -f "$NOTAS"' EXIT
# Las novedades de cada versión salen de docs/CAMBIOS.md, no se escriben aquí:
# una lista de cambios pegada a mano en el script de publicar se queda con la
# de la versión anterior el día que alguien tiene prisa.
NOVEDADES=""
if [ -f "$RAIZ/docs/CAMBIOS.md" ]; then
    # Desde el primer "## " que nombre esta etiqueta hasta el siguiente "## ".
    NOVEDADES="$(awk -v v="$ETIQUETA" '
        $0 ~ "^## " && index($0, v) { dentro=1; next }
        dentro && /^## / { exit }
        dentro { print }
    ' "$RAIZ/docs/CAMBIOS.md")"
fi

cat > "$NOTAS" <<NOTAS_FIN
Imagen arrancable de MIKE OS. Arranca en memoria: puedes probar el sistema
entero sin tocar el disco.

$NOVEDADES

## Descargar

| | |
|---|---|
| Archivo | \`mikeos.iso\` ($TAM) |
| Kernel | \`$KVER\` |
| Código | [\`$COMMIT\`](https://github.com/$REPO/commit/$COMMIT) |

\`\`\`
SHA256  $SHA
\`\`\`

## Grabarla en un USB

\`\`\`sh
sha256sum mikeos.iso     # compara con el de arriba antes de nada
sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync
\`\`\`

\`/dev/sdX\` es tu USB y **se borra entero**. Compruébalo con \`lsblk\`.

## Hay que desactivar Secure Boot

Este kernel no lleva la firma de Microsoft, así que con Secure Boot activado la
firmware se niega a ejecutarlo.

En una Surface: apágala del todo, mantén **subir volumen** y pulsa encendido;
suelta cuando aparezca el logo. En *Security*, Secure Boot a *Disabled*. En
*Boot configuration*, sube *USB Storage* por encima del disco interno.

En otros equipos la tecla suele ser Supr, F2 o F12 nada más encender.

## Instalarlo

Arranca el USB y pulsa **Instalar** en la ventana de bienvenida: el instalador
es gráfico, detecta el disco solo y avisa de lo que va a borrar antes de
borrarlo. Si prefieres la terminal, \`m-install\` sigue ahí.

Propone **btrfs**, porque es lo que permite que \`mpm\` tome una instantánea del
sistema antes de cada instalación y que \`mpm rollback\` vuelva atrás de verdad.

## Qué esperar

Versión **alpha**. Arranca en hardware UEFI real, se instala y se actualiza,
pero no hay versión estable ni promesa de que no se rompa nada entre una y
otra. **Instálalo en un equipo que puedas formatear.**

Sin gestor de arranque: el kernel lleva \`CONFIG_EFI_STUB\` y es su propio
ejecutable UEFI.

---

[Web](https://m1keos.duckdns.org/) ·
[Documentación](https://m1keos.duckdns.org/docs/) ·
[Wiki](https://m1keos.duckdns.org/wiki/) ·
[Reportar un fallo](https://github.com/$REPO/issues/new/choose)
NOTAS_FIN

# --- Publicar ---------------------------------------------------------------
paso "Creando la release $ETIQUETA"
if gh release view "$ETIQUETA" --repo "$REPO" >/dev/null 2>&1; then
    gris "  ya existe: se sustituye el archivo"
    gh release upload "$ETIQUETA" "$ISO" "$ISO.sha256" --repo "$REPO" --clobber || exit 1
else
    gh release create "$ETIQUETA" "$ISO" "$ISO.sha256" \
        --repo "$REPO" \
        --title "MIKE OS $ETIQUETA" \
        --notes-file "$NOTAS" \
        $BORRADOR $PRUEBA || exit 1
fi

URL="https://github.com/$REPO/releases/download/$ETIQUETA/mikeos.iso"
echo
paso "Comprobando que se descarga"
CODIGO=$(curl -fsSL --max-time 30 -o /dev/null -w '%{http_code}' -r 0-1023 "$URL" 2>/dev/null || echo "---")
if [ "$CODIGO" = "206" ] || [ "$CODIGO" = "200" ]; then
    verde "  $URL responde ($CODIGO)"
else
    gris "  todavía no responde ($CODIGO); GitHub tarda unos segundos en propagarla"
fi

echo
verde "Publicada: https://github.com/$REPO/releases/tag/$ETIQUETA"
gris "Enlace de descarga directa (sin página intermedia):"
gris "  $URL"
