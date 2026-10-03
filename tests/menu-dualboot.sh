#!/bin/bash
# ¿Encuentra el instalador a Windows (y a los demás) para el menú de GRUB?
#
# Saca de m-install el bucle que recorre la partición EFI buscando otros
# cargadores y lo ejecuta contra una partición de mentira. Fallos que ya hubo
# o que estaban a punto:
#   - buscar a dos niveles no encontraba EFI/Microsoft/Boot/bootmgfw.efi;
#   - "for x in $(find ...)" partía por espacios: "EFI/HP Recovery" se perdía;
#   - "chainloader /EFI/HP Recovery/x.efi" sin comillas: GRUB lo parte en dos.
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/EFI/Microsoft/Boot" "$T/EFI/HP Recovery" "$T/EFI/mikeos" "$T/EFI/BOOT" "$T/EFI/ubuntu"
touch "$T/EFI/Microsoft/Boot/bootmgfw.efi" "$T/EFI/HP Recovery/grubx64.efi" \
      "$T/EFI/mikeos/grubx64.efi" "$T/EFI/BOOT/BOOTX64.EFI" "$T/EFI/ubuntu/shimx64.efi" \
      "$T/EFI/HP Recovery/herramienta.efi"

M="$RAIZ/build/mcore/m-install"
I=$(grep -n 'maxdepth 3 -type f' "$M" | head -1 | cut -d: -f1)
F=$(grep -n 'rm -f /tmp/m-install-efis.txt' "$M" | head -1 | cut -d: -f1)
[ -n "$I" ] && [ -n "$F" ] || { echo "No encuentro el bucle en m-install (¿ha cambiado?)."; exit 1; }
sed -n "${I},${F}p" "$M" | sed "s|/tmp/m-install-efis.txt|$T/lista.txt|g" > "$T/bucle.sh"
bash -c "m_entrada(){ printf %s \"\$1\"; }; _tmp='$T'; _uuid=ABCD-1234; _n_otros=0; . '$T/bucle.sh'; echo \"#n=\$_n_otros\"" > "$T/menu.cfg"

MAL=0
chk() { if grep -qF -- "$2" "$T/menu.cfg"; then echo "  ✓ $1"; else echo "  ✗ $1"; MAL=1; fi; }
chk "encuentra Windows"                       'chainloader "/EFI/Microsoft/Boot/bootmgfw.efi"'
chk "y una carpeta con espacio en el nombre"  'chainloader "/EFI/HP Recovery/grubx64.efi"'
chk "y otra distribución"                     'chainloader "/EFI/ubuntu/shimx64.efi"'
chk "cuenta los tres"                          '#n=3'
if grep -qE 'EFI/mikeos|EFI/BOOT|herramienta' "$T/menu.cfg"; then echo "  ✗ se cuela algo que no es otro sistema"; MAL=1; else echo "  ✓ y no mete los nuestros ni herramientas sueltas"; fi
if command -v grub-script-check >/dev/null; then
    sed -i '/^#n=/d' "$T/menu.cfg"
    grub-script-check "$T/menu.cfg" && echo "  ✓ GRUB lo da por válido" || { echo "  ✗ GRUB no lo acepta"; MAL=1; }
fi
exit $MAL
