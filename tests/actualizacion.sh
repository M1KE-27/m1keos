#!/bin/bash
# ==============================================================================
# Prueba de la cadena de actualización, de punta a punta.
#
# Responde a una pregunta concreta: si cambio una línea del código en mi equipo,
# ¿llega a una máquina que ya tiene MIKE OS instalado, sin reinstalar nada?
#
# Lo comprueba de verdad:
#   1. Mete una marca reconocible en el código de mpm.
#   2. Construye los paquetes y los sirve por HTTP, como haría el mini PC.
#   3. Desde la máquina virtual: mpm source add, mpm update, mpm upgrade.
#   4. Mira si la marca está dentro del /usr/bin/mpm de la máquina.
#   5. Deja el código como estaba.
#
# El caso interesante es precisamente ese: mpm actualizándose a sí mismo
# mientras está en marcha.
#
#   ./tests/actualizacion.sh        (necesita una VM arrancada; ./tests/humo.sh --dejar)
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAVE="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"
PUERTO="${MIKEOS_DEV_PORT:-2222}"
# 10.0.2.2 es el anfitrión visto desde dentro de la red de usuario de QEMU.
PUERTO_HTTP="${MIKEOS_HTTP:-8099}"
URL_REPO="http://10.0.2.2:$PUERTO_HTTP/"
MARCA="marca-de-prueba-$(date +%s)"

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }

vm() {
    ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 \
        mike@localhost \
        "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; $*" 2>&1
}

limpiar() {
    [ -n "${HTTP_PID:-}" ] && kill "$HTTP_PID" 2>/dev/null
    [ -f "$RAIZ/build/mpm/mpm.antes" ] && mv -f "$RAIZ/build/mpm/mpm.antes" "$RAIZ/build/mpm/mpm"
}
trap limpiar EXIT

vm true >/dev/null 2>&1 || { rojo "No hay ninguna VM respondiendo en el puerto $PUERTO."; exit 1; }

# --- 1. El cambio ------------------------------------------------------------
paso "Metiendo una marca en el código de mpm"
cp "$RAIZ/build/mpm/mpm" "$RAIZ/build/mpm/mpm.antes"
# Una orden nueva, que es la forma más clara de demostrar que el código que
# corre en la máquina es el nuevo y no el que venía en la imagen.
python3 - "$RAIZ/build/mpm/mpm" "$MARCA" <<'PY'
import sys
ruta, marca = sys.argv[1], sys.argv[2]
s = open(ruta).read()
ancla = 'case "$CMD" in\n    search)'
nuevo = 'case "$CMD" in\n    marca)\n        echo "%s"\n        ;;\n    search)' % marca
assert ancla in s, "no encuentro dónde insertar la marca"
open(ruta, "w").write(s.replace(ancla, nuevo, 1))
PY
gris "  marca: $MARCA"

# Subir la versión, o "upgrade" no verá nada nuevo que instalar.
VER_ANTES="$(grep -m1 -A2 '"name": "mpm"' "$RAIZ/scripts/build-repo.sh" >/dev/null 2>&1; echo)"
sed -i 's/^\[ -n "\$MPM_VER" \] || MPM_VER="0.2.0"/[ -n "$MPM_VER" ] || MPM_VER="0.2.1"/' \
    "$RAIZ/scripts/build-repo.sh"

# --- 2. Construir y servir ---------------------------------------------------
paso "Construyendo los paquetes"
if ! "$RAIZ/scripts/build-repo.sh" > "${TMPDIR:-/tmp}/mikeos-act.log" 2>&1; then
    rojo "  falló la construcción"; tail -15 "${TMPDIR:-/tmp}/mikeos-act.log"; exit 1
fi
verde "  paquetes listos"

paso "Sirviendo el repositorio por HTTP (hace de mini PC)"
( cd "$RAIZ/build/repo" && python3 -m http.server "$PUERTO_HTTP" >/dev/null 2>&1 ) &
HTTP_PID=$!
sleep 2
curl -fsS --max-time 5 "${URL_REPO}repo.json" -o /dev/null 2>/dev/null \
    && verde "  ${URL_REPO}repo.json responde" \
    || { rojo "  el servidor local no responde"; exit 1; }

# --- 3. Desde la máquina -----------------------------------------------------
paso "En la máquina: añadiendo la fuente y actualizando"
gris "  antes:  $(vm 'mpm marca 2>&1 | head -1' | head -1)"

vm "m-sudo mpm source add '$URL_REPO'" >/dev/null 2>&1
SALIDA_UPDATE="$(vm 'm-sudo mpm update 2>&1 | tail -5')"
gris "  $(printf '%s' "$SALIDA_UPDATE" | tr '\n' '|')"

paso "Instalando la versión nueva de mpm (se actualiza a sí mismo)"
SALIDA="$(vm 'm-sudo mpm install -y mpm 2>&1 | tail -8')"
printf '%s\n' "$SALIDA" | sed 's/^/    /'

# --- 4. ¿Llegó? --------------------------------------------------------------
echo
paso "Comprobando el resultado"
DESPUES="$(vm 'mpm marca 2>&1 | head -1')"
printf '  %-40s' "la orden nueva existe en la máquina"
if printf '%s' "$DESPUES" | grep -q "$MARCA"; then
    verde "✓  devuelve $MARCA"
    RC=0
else
    rojo "✗  devuelve: $DESPUES"
    RC=1
fi

printf '  %-40s' "mpm sigue funcionando tras actualizarse"
if vm 'mpm list >/dev/null 2>&1 && echo ok' | grep -q ok; then
    verde "✓"
else
    rojo "✗  mpm quedó roto"
    RC=1
fi

echo
if [ "$RC" -eq 0 ]; then
    verde "Cadena completa: código editado aquí → paquete → servidor → mpm upgrade → máquina."
else
    rojo "La cadena de actualización NO funciona."
fi
exit "$RC"
