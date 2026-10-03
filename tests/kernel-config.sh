#!/bin/bash
# ¿El kernel lleva de verdad lo que pide el fragmento?
#
# Por qué existe
# --------------
# build.sh hace "make defconfig", mezcla encima el fragmento .config y luego
# "make olddefconfig". Ese último paso TIRA EN SILENCIO cualquier opción a la
# que le falte una dependencia, y también las que ya no existen. No avisa, no
# falla: el kernel compila igual, sólo que sin el driver.
#
# Así se perdieron, durante semanas y sin un solo mensaje:
#   - TG3 (Ethernet Broadcom): el símbolo se llama TIGON3. Con el nombre mal,
#     no estuvo nunca.
#   - AMD_PMF: exige TEE y AMDTEE, que no estaban.
#   - VBOXGUEST: vive dentro del menú VIRT_DRIVERS, que estaba apagado.
#   - Todo Dell: DCDBAS vale "m" por defecto y arrastraba al resto a módulo.
#     Y aquí un módulo es un driver que no existe: no se monta /lib/modules.
#
# Esto repite los mismos tres pasos sobre una copia aparte (no toca el árbol
# del kernel ni su .config) y compara opción por opción.
#
#   ./tests/kernel-config.sh
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$RAIZ/kernel"
FRAG="$RAIZ/.config"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SIM="$TMP/sim.config"

[ -f "$KERNEL/Makefile" ] || { echo "No hay árbol del kernel en $KERNEL (se clona con ./scripts/build.sh)."; exit 2; }

# Una opción escrita DOS veces en el fragmento: si algún día se cambia sólo
# una, gana la última en silencio (kconfig sólo dice "override" entre cientos
# de líneas de compilación).
REPES="$(grep -oE '^(# )?CONFIG_[A-Za-z0-9_]+' "$FRAG" | sed 's/^# //' | sort | uniq -d)"
if [ -n "$REPES" ]; then
    echo "Opciones escritas más de una vez en .config:"; printf '    %s\n' $REPES
    exit 1
fi

# 1. defconfig, 2. el fragmento encima, 3. olddefconfig --- igual que build.sh.
make -s -C "$KERNEL" KCONFIG_CONFIG="$SIM" defconfig >/dev/null 2>&1 \
    || { echo "make defconfig falló"; exit 2; }
grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set)' "$FRAG" > "$TMP/pedido"
while IFS= read -r l; do
    k="$(printf '%s' "$l" | sed -E 's/^# (CONFIG_[A-Za-z0-9_]+) is not set$/\1/; s/=.*//')"
    sed -i "/^$k=/d; /^# $k is not set$/d" "$SIM"
done < "$TMP/pedido"
cat "$TMP/pedido" >> "$SIM"
make -s -C "$KERNEL" KCONFIG_CONFIG="$SIM" olddefconfig >/dev/null 2>&1 \
    || { echo "make olddefconfig falló"; exit 2; }

MAL=0; OK=0
while IFS= read -r l; do
    case "$l" in "#"*) continue ;; esac
    k="${l%%=*}"; v="${l#*=}"
    r="$(grep -E "^$k=" "$SIM" | head -1 | cut -d= -f2-)"
    case "$v" in
        n) [ -z "$r" ] && { OK=$((OK+1)); continue; } ;;
        *) [ "$r" = "$v" ] && { OK=$((OK+1)); continue; } ;;
    esac
    # ¿No existe, o le falta algo?
    if grep -rqE "^(menu)?config ${k#CONFIG_}$" --include='Kconfig*' "$KERNEL" 2>/dev/null; then
        motivo="se cae (falta una dependencia)"
    else
        motivo="NO EXISTE en este kernel"
    fi
    printf '  \033[31m✗\033[0m %-40s pedido=%-4s queda=%-8s %s\n' "$k" "$v" "${r:-nada}" "$motivo"
    MAL=$((MAL+1))
done < "$TMP/pedido"

# Y lo que nadie pidió pero se quedó como módulo: aquí eso es no tenerlo.
MODS="$(grep -c '=m$' "$SIM" || true)"

echo
printf '%d de %d opciones del fragmento acaban en el kernel.\n' "$OK" "$((OK+MAL))"
if [ "$MODS" -gt 0 ]; then
    printf '%d opciones quedan como módulo (y aquí los módulos no se cargan):\n' "$MODS"
    grep '=m$' "$SIM" | sed 's/^/    /'
fi
[ "$MAL" -eq 0 ]
