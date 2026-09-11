#!/bin/bash
# ==============================================================================
# actualizar-kernel.sh - traer el kernel nuevo de upstream sin perder lo nuestro.
#
# Lo bueno de cómo está montado MIKE OS: nuestras modificaciones al kernel NO
# son parches al código fuente. Son una lista de opciones en el archivo
# ".config" de la raíz del proyecto, que se fusiona sobre el defconfig de cada
# versión. Eso significa que actualizar no es rebasar parches ni resolver
# conflictos: es traer el árbol nuevo y volver a aplicar la misma lista.
#
# Si algún día hiciera falta un parche de verdad (algo que upstream no tiene),
# iría en kernel-parches/*.patch y este script lo aplicaría después de la
# actualización, avisando si deja de aplicar limpiamente.
#
#   ./scripts/actualizar-kernel.sh              va a la última de la rama master
#   ./scripts/actualizar-kernel.sh v6.18        va a una etiqueta concreta
#   ./scripts/actualizar-kernel.sh --ver        dice qué hay de nuevo, sin tocar
#   ./scripts/actualizar-kernel.sh --volver     regresa al kernel anterior
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$RAIZ/kernel"
FRAGMENTO="$RAIZ/.config"
PARCHES="$RAIZ/kernel-parches"
GUARDADO="$RAIZ/build/kernel-anterior"

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }

[ -d "$KERNEL/.git" ] || { rojo "No hay repositorio git en $KERNEL."; exit 1; }

DESTINO="${1:-master}"
SOLO_VER=0
case "$DESTINO" in
    --ver)    SOLO_VER=1; DESTINO="master" ;;
    --volver)
        paso "Volviendo al kernel anterior"
        if [ ! -f "$GUARDADO/bzImage" ]; then
            rojo "No hay ningún kernel guardado en $GUARDADO."; exit 1
        fi
        cp "$GUARDADO/bzImage" "$KERNEL/arch/x86/boot/bzImage"
        cp "$GUARDADO/.config" "$KERNEL/.config"
        verde "Restaurado el kernel $(cat "$GUARDADO/version" 2>/dev/null)."
        exit 0
        ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

ACTUAL="$(cd "$KERNEL" && git rev-parse --short HEAD 2>/dev/null)"
VERSION_ACTUAL="$(cat "$KERNEL/include/config/kernel.release" 2>/dev/null || echo desconocida)"
gris "  ahora: $VERSION_ACTUAL ($ACTUAL)"

# --- Traer upstream ----------------------------------------------------------
paso "Trayendo los cambios de kernel.org / torvalds"
(cd "$KERNEL" && git fetch --tags origin 2>&1 | tail -3) || { rojo "falló el fetch"; exit 1; }

NUEVO="$(cd "$KERNEL" && git rev-parse --short "origin/$DESTINO" 2>/dev/null || git rev-parse --short "$DESTINO" 2>/dev/null)"
[ -n "$NUEVO" ] || { rojo "No encuentro '$DESTINO' en el repositorio."; exit 1; }

if [ "$ACTUAL" = "$NUEVO" ]; then
    verde "Ya estás en lo último ($NUEVO). No hay nada que traer."
    exit 0
fi

N_COMMITS="$(cd "$KERNEL" && git rev-list --count "$ACTUAL..$NUEVO" 2>/dev/null || echo "?")"
gris "  nuevo: $NUEVO  ($N_COMMITS commits por delante)"

if [ "$SOLO_VER" -eq 1 ]; then
    echo
    paso "Últimos cambios que entrarían"
    (cd "$KERNEL" && git log --oneline "$ACTUAL..$NUEVO" | head -15 | sed 's/^/    /')
    echo
    gris "Sólo era una ojeada. Para aplicarlo: ./scripts/actualizar-kernel.sh $DESTINO"
    exit 0
fi

# --- Guardar el actual, que es la única vuelta atrás -------------------------
paso "Guardando el kernel actual antes de tocar nada"
mkdir -p "$GUARDADO"
[ -f "$KERNEL/arch/x86/boot/bzImage" ] && cp "$KERNEL/arch/x86/boot/bzImage" "$GUARDADO/bzImage"
cp "$KERNEL/.config" "$GUARDADO/.config" 2>/dev/null || true
echo "$VERSION_ACTUAL" > "$GUARDADO/version"
verde "  guardado en $GUARDADO"

# --- Cambiar de versión ------------------------------------------------------
paso "Cambiando a $DESTINO"
(cd "$KERNEL" && git checkout -q --detach "$NUEVO") || { rojo "falló el checkout"; exit 1; }

# --- Volver a aplicar nuestras opciones --------------------------------------
# Aquí está la gracia: no se rebasa nada. Se parte del defconfig de la versión
# nueva y se le vuelve a fusionar nuestra lista.
paso "Reaplicando la configuración de MIKE OS"
(cd "$KERNEL" && make defconfig >/dev/null 2>&1) || { rojo "falló defconfig"; exit 1; }
(cd "$KERNEL" && ./scripts/kconfig/merge_config.sh -m .config "$FRAGMENTO" >/dev/null 2>&1)
(cd "$KERNEL" && make olddefconfig >/dev/null 2>&1)

# --- Comprobar qué se ha perdido por el camino -------------------------------
# Entre versiones del kernel las opciones se renombran, se fusionan o se
# retiran. Una opción nuestra que deje de existir desaparece en silencio, y el
# fallo no aparece hasta que alguien enchufa el portátil y no tiene WiFi. Por
# eso se comprueba una por una.
paso "Comprobando que nuestras opciones siguen existiendo"
PERDIDAS=0
while IFS= read -r linea; do
    case "$linea" in
        CONFIG_*=y)
            clave="${linea%%=*}"
            grep -q "^$clave=y" "$KERNEL/.config" || {
                printf '    \033[31m✗\033[0m %s\n' "$clave"
                PERDIDAS=$((PERDIDAS + 1))
            }
            ;;
    esac
done < "$FRAGMENTO"

if [ "$PERDIDAS" -eq 0 ]; then
    verde "  las $(grep -c '^CONFIG_.*=y' "$FRAGMENTO") opciones siguen en pie"
else
    rojo "  $PERDIDAS opción(es) ya no existen o no se pudieron activar"
    gris "  Suelen ser opciones renombradas en upstream. Hay que buscar el"
    gris "  nombre nuevo y corregir .config antes de dar esto por bueno."
fi

# --- Parches propios, si los hubiera -----------------------------------------
if [ -d "$PARCHES" ] && ls "$PARCHES"/*.patch >/dev/null 2>&1; then
    paso "Aplicando los parches propios"
    for parche in "$PARCHES"/*.patch; do
        if (cd "$KERNEL" && git apply --check "$parche" 2>/dev/null); then
            (cd "$KERNEL" && git apply "$parche")
            verde "  ✓ $(basename "$parche")"
        else
            rojo "  ✗ $(basename "$parche") ya no aplica limpiamente"
            gris "    Hay que rehacerlo contra el árbol nuevo."
            PERDIDAS=$((PERDIDAS + 1))
        fi
    done
fi

# --- Compilar ----------------------------------------------------------------
paso "Compilando (esto tarda)"
if (cd "$KERNEL" && make -j"$(nproc)" bzImage > "${TMPDIR:-/tmp}/mikeos-kernel.log" 2>&1); then
    NUEVA_VER="$(cat "$KERNEL/include/config/kernel.release" 2>/dev/null)"
    verde "  compilado: $NUEVA_VER"
else
    rojo "  falló la compilación. Registro en ${TMPDIR:-/tmp}/mikeos-kernel.log"
    tail -20 "${TMPDIR:-/tmp}/mikeos-kernel.log" >&2
    gris "  Para volver atrás: ./scripts/actualizar-kernel.sh --volver"
    exit 1
fi

# --- Fijar el commit en build.sh, para que el build sea reproducible ---------
paso "Fijando el commit nuevo en scripts/build.sh"
COMMIT_LARGO="$(cd "$KERNEL" && git rev-parse HEAD)"
sed -i "s/^KERNEL_COMMIT=\".*\"/KERNEL_COMMIT=\"$COMMIT_LARGO\"/" "$RAIZ/scripts/build.sh"
verde "  KERNEL_COMMIT=$COMMIT_LARGO"

echo
if [ "$PERDIDAS" -eq 0 ]; then
    verde "Kernel actualizado de $VERSION_ACTUAL a $NUEVA_VER."
else
    rojo "Kernel actualizado, pero con $PERDIDAS aviso(s) que revisar arriba."
fi
gris "Siguiente paso: ./scripts/build.sh && ./tests/humo.sh"
gris "Si algo va mal:  ./scripts/actualizar-kernel.sh --volver"
