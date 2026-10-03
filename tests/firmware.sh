#!/bin/bash
# ¿Lleva la imagen el firmware que piden sus drivers?
#
# Por qué existe
# --------------
# Aquí todo driver va compilado dentro del kernel, y muchos no hacen nada sin
# su firmware. La imagen copia ese firmware desde el /lib/firmware del equipo
# que compila, con una lista de patrones --- y esa lista llevaba semanas
# rota sin que se notara:
#
#   "ath10k/*" sólo encuentra CARPETAS (QCA6174/, QCA9377/...), y el bucle se
#   saltaba las carpetas. Los archivos de verdad están un nivel más abajo, así
#   que el Wi-Fi Qualcomm/Atheros --- de los más comunes en portátiles --- no
#   tuvo firmware nunca. Lo mismo mediatek/mt7925/, el Wi-Fi 7 de MediaTek.
#   Y el comentario del script decía que sí estaban.
#
# Un driver sin su firmware no da ningún error al compilar ni al arrancar en
# una máquina virtual: sólo en el portátil que lleva esa tarjeta, y allí lo
# único que se ve es que no hay Wi-Fi.
#
# Los drivers compilados dentro dejan escrito qué firmware pueden pedir
# (kernel/modules.builtin.modinfo). Esto lo cruza con lo que lleva la imagen.
#
# La regla que hace fallar la prueba: un driver que declara firmware y NO
# TIENE NI UNO en la imagen. Que falten algunos es normal (cada driver
# declara las variantes de chips de diez años); que falten todos es que ese
# driver no sirve para nada.
#
#   ./tests/firmware.sh            resumen y fallos
#   ./tests/firmware.sh -v         además, cobertura de cada driver
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODINFO="$RAIZ/kernel/modules.builtin.modinfo"
FW="$RAIZ/rootfs/lib/firmware"
VERBOSO=0; [ "${1:-}" = "-v" ] && VERBOSO=1

[ -f "$MODINFO" ] || { echo "Falta $MODINFO: compila el kernel primero (./scripts/build.sh)."; exit 2; }
[ -d "$FW" ]      || { echo "Falta $FW: construye la imagen primero (./scripts/build.sh)."; exit 2; }

# Drivers que sabemos que no aplican a un PC o portátil x86 y que por eso no
# llevan firmware a propósito. Cada uno con su motivo: sin motivo, no entra.
IGNORAR="
qat_4xxx qat_420xx qat_c3xxx qat_c62x qat_dh895xcc  # aceleradores criptográficos de servidor
ice                                                  # tarjetas de red de centro de datos (E810)
bnx2x                                                # Broadcom 10 Gb de servidor
ccp                                                  # sólo pide el firmware SEV de los EPYC de servidor (cifrado de VMs)
"

python3 - "$MODINFO" "$FW" "$VERBOSO" "$IGNORAR" <<'PY'
import os, sys, glob, collections
modinfo, fw, verboso, ignorar = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
ign = set()
for l in ignorar.splitlines():
    l = l.split("#")[0].split()
    ign.update(l)

pedidos = collections.defaultdict(set)
for e in open(modinfo, "rb").read().split(b"\0"):
    e = e.decode("utf-8", "replace")
    if ".firmware=" not in e:
        continue
    drv, nom = e.split(".firmware=", 1)
    pedidos[drv].add(nom)

def esta(nom):
    base = os.path.join(fw, nom)
    for suf in ("", ".zst", ".xz"):
        if "*" in nom or "?" in nom:
            if glob.glob(base + suf):
                return True
        elif os.path.exists(base + suf):
            return True
    return False

filas, rotos = [], []
for drv in sorted(pedidos):
    n = len(pedidos[drv])
    ok = sum(1 for f in pedidos[drv] if esta(f))
    filas.append((drv, ok, n))
    if ok == 0 and drv not in ign:
        rotos.append((drv, n, sorted(pedidos[drv])[:3]))

tot = sum(n for _, _, n in filas); hay = sum(ok for _, ok, _ in filas)
print("%d drivers declaran firmware; la imagen lleva %d de los %d archivos que pueden pedir."
      % (len(filas), hay, tot))

if verboso:
    print()
    for drv, ok, n in sorted(filas, key=lambda x: (x[1] / x[2], x[0])):
        marca = "✗" if ok == 0 else ("·" if ok < n else "✓")
        print("  %s %-24s %4d / %-4d" % (marca, drv, ok, n))

if rotos:
    print()
    print("\033[31mDrivers compilados dentro SIN NINGUNO de sus firmware\033[0m "
          "(no funcionan con ningún dispositivo):")
    for drv, n, ej in rotos:
        print("  \033[31m✗\033[0m %-22s 0 de %-4d  p. ej. %s" % (drv, n, ", ".join(ej)))
    sys.exit(1)
print("Ningún driver se ha quedado sin firmware.")
PY
