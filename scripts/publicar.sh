#!/bin/bash
# ==============================================================================
# publicar.sh - de "he cambiado algo" a "ya se lo pueden bajar".
#
# Construye los paquetes, regenera el índice y lo sube al mini PC de casa, que
# es lo que consultan todos los equipos con MIKE OS al hacer "mpm upgrade".
#
# La idea: tú tocas el código aquí; quien quiera la actualización la pide. No
# se empuja nada a nadie.
#
#   ./scripts/publicar.sh              construye, sube y regenera el índice
#   ./scripts/publicar.sh --local      sólo construye y deja el repo listo aquí
#   ./scripts/publicar.sh --ver        enseña qué se subiría, sin subir nada
#
# En el equipo que recibe:
#   mpm source add https://m1keos.duckdns.org/mpm/
#   mpm update && mpm upgrade
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# El servidor no va escrito aquí: esto es un repositorio público y la dirección
# del equipo de casa de cada uno no pinta nada en él. Se pone en
# .publicar.conf (que no se versiona) o en la variable MIKEOS_SERVIDOR.
[ -f "$RAIZ/.publicar.conf" ] && . "$RAIZ/.publicar.conf"
SERVIDOR="${MIKEOS_SERVIDOR:-}"
if [ -z "$SERVIDOR" ]; then
    err "no sé a qué servidor subir."
    gris "  Crea $RAIZ/.publicar.conf con:"
    gris "      MIKEOS_SERVIDOR=usuario@tu-servidor"
    gris "  o exporta MIKEOS_SERVIDOR antes de ejecutar esto."
    exit 1
fi
# Es la carpeta que sirve nginx en m1keos.duckdns.org, bajo /mpm/.
# /home/m1ke es escribible sin sudo; /var/www y /srv no lo son en ese equipo.
DESTINO="${MIKEOS_SERVIDOR_DIR:-/home/m1ke/mikeos-backend/web/mpm}"
REPO_LOCAL="$RAIZ/build/repo"

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }
err()   { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

SOLO_LOCAL=0
SOLO_VER=0
for a in "$@"; do
    case "$a" in
        --local) SOLO_LOCAL=1 ;;
        --ver)   SOLO_VER=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) err "opción desconocida: $a"; exit 2 ;;
    esac
done

# --- 1. Construir los paquetes -----------------------------------------------
paso "Construyendo los paquetes"
if ! "$RAIZ/scripts/build-repo.sh" > "${TMPDIR:-/tmp}/mikeos-publicar.log" 2>&1; then
    err "falló la construcción. Registro en ${TMPDIR:-/tmp}/mikeos-publicar.log"
    tail -20 "${TMPDIR:-/tmp}/mikeos-publicar.log" >&2
    exit 1
fi
verde "  paquetes listos"

[ -f "$REPO_LOCAL/repo.json" ] || { err "no hay índice en $REPO_LOCAL/repo.json"; exit 1; }

# --- 2. Qué hay dentro -------------------------------------------------------
paso "Contenido del repositorio"
N=0
while IFS= read -r mpk; do
    printf '    %-46s %s\n' "$(basename "$mpk")" "$(du -h "$mpk" | cut -f1)"
    N=$((N + 1))
done < <(find "$REPO_LOCAL" -name '*.mpk' | sort)
gris "    $N paquete(s), $(du -sh "$REPO_LOCAL" | cut -f1) en total"

if [ "$SOLO_VER" -eq 1 ]; then
    echo
    gris "Sólo era una ojeada: no se ha subido nada."
    exit 0
fi
if [ "$SOLO_LOCAL" -eq 1 ]; then
    echo
    verde "Repositorio listo en $REPO_LOCAL"
    exit 0
fi

# --- 3. Subir ----------------------------------------------------------------
paso "Subiendo a $SERVIDOR:$DESTINO"
if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$SERVIDOR" true 2>/dev/null; then
    err "no se puede entrar en $SERVIDOR sin contraseña."
    gris "  Prueba: ssh-copy-id $SERVIDOR"
    exit 1
fi

ssh "$SERVIDOR" "mkdir -p '$DESTINO'" || exit 1

# rsync si está; si no, tar por la tubería de ssh, que va en cualquier equipo.
if command -v rsync >/dev/null 2>&1 && ssh "$SERVIDOR" 'command -v rsync' >/dev/null 2>&1; then
    rsync -a --delete --info=stats1 "$REPO_LOCAL/" "$SERVIDOR:$DESTINO/" || exit 1
else
    gris "  sin rsync: se envía comprimido por ssh"
    tar -C "$REPO_LOCAL" -czf - . | ssh "$SERVIDOR" "rm -rf '$DESTINO'/* && tar -C '$DESTINO' -xzf -" || exit 1
fi
verde "  subido"

# --- 4. Comprobar que se sirve de verdad -------------------------------------
# Subir los archivos no basta: si nadie los está sirviendo por HTTP, "mpm
# update" seguirá viendo el índice viejo o ninguno. Mejor enterarse aquí.
paso "Comprobando que el índice se sirve"
URL="${MIKEOS_REPO_URL:-https://m1keos.duckdns.org/mpm/repo.json}"
if curl -fsS --max-time 12 "$URL" -o /dev/null 2>/dev/null; then
    verde "  $URL responde"
    echo
    verde "Publicado. En cualquier equipo con MIKE OS:"
    echo "    mpm update && mpm upgrade"
else
    echo
    gris "  $URL todavía no responde."
    gris "  Los archivos están en $SERVIDOR:$DESTINO, pero falta que algo los"
    gris "  sirva por HTTP en esa ruta (ver Bloque 14 del plan: mikeos.duckdns.org)."
fi
