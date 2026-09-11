#!/bin/bash
# ==============================================================================
# crear-iso.sh - genera el USB/ISO arrancable de MIKE OS.
#
# Es lo que faltaba para que el sistema exista fuera de QEMU: hasta ahora la
# única forma de verlo era que QEMU le pasara el kernel en la mano
# (-kernel bzImage -initrd ...). Un ISO se puede grabar en un USB y arrancar
# en un portátil de verdad, probar el sistema sin instalar nada, y desde ahí
# lanzar m-install.
#
# No lleva gestor de arranque. El kernel de MIKE OS se compila con
# CONFIG_EFI_STUB, así que él mismo es un ejecutable UEFI válido: se mete en
# una imagen FAT32 como EFI/BOOT/BOOTX64.EFI y la firmware lo arranca. Un GRUB
# menos que mantener.
#
# La ISO es híbrida: sirve tanto grabada en un USB (dd) como montada.
#
#   ./scripts/crear-iso.sh
#   sudo dd if=iso/mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync
#
# Aviso: en equipos con Secure Boot activado (las Surface vienen así) hay que
# desactivarlo en la UEFI. Este kernel no lleva la firma de Microsoft.
# ==============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$RAIZ/kernel/arch/x86/boot/bzImage"
INITRAMFS="$RAIZ/iso/initramfs.cpio.gz"
SALIDA="$RAIZ/iso/mikeos.iso"
TRABAJO="$(mktemp -d "${TMPDIR:-/tmp}/mikeos-iso-XXXXXX")"
trap 'rm -rf "$TRABAJO"' EXIT

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }
err()   { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

for t in xorriso mkfs.vfat; do
    command -v "$t" >/dev/null 2>&1 || { err "falta $t"; exit 1; }
done
[ -f "$KERNEL" ]    || { err "no hay kernel en $KERNEL. Ejecuta ./scripts/build.sh"; exit 1; }
[ -f "$INITRAMFS" ] || { err "no hay initramfs. Ejecuta ./scripts/build.sh"; exit 1; }

paso "Preparando el contenido"
mkdir -p "$TRABAJO/raiz/EFI/BOOT" "$TRABAJO/raiz/EFI/mikeos" "$TRABAJO/raiz/mikeos"
cp "$KERNEL"    "$TRABAJO/raiz/EFI/BOOT/BOOTX64.EFI"
cp "$KERNEL"    "$TRABAJO/raiz/EFI/mikeos/vmlinuz.efi"
cp "$INITRAMFS" "$TRABAJO/raiz/EFI/mikeos/initramfs.cpio.gz"
cp "$INITRAMFS" "$TRABAJO/raiz/mikeos/initramfs.cpio.gz"

# El sistema vive en el propio initramfs, así que arranca en RAM y no necesita
# tocar ningún disco: es lo que permite probarlo sin instalar nada.
CMDLINE="root=/dev/ram0 rw console=tty0 quiet mikeos_gui=1"
printf '%s' "$CMDLINE" > "$TRABAJO/raiz/EFI/BOOT/cmdline.txt"
printf '%s' "$CMDLINE" > "$TRABAJO/raiz/EFI/mikeos/cmdline.txt"

cat > "$TRABAJO/raiz/LEEME.txt" <<EOF
MIKE OS — medio de instalación

Esto arranca en memoria: puedes probar el sistema sin tocar el disco.
Para instalarlo, abre una terminal (SUPER/ALT + Return) y escribe:

    m-install /dev/nvme0n1        (o el disco que corresponda; m-install los lista)

En equipos con Secure Boot activado hay que desactivarlo antes en la UEFI.
Este kernel no lleva la firma de Microsoft.

https://m1keos.duckdns.org
EOF

# --- Imagen EFI ---------------------------------------------------------------
# La firmware UEFI no lee ISO9660: busca una partición FAT dentro del medio.
# Se crea esa imagen FAT con el kernel dentro y se incrusta en la ISO.
paso "Creando la imagen de arranque EFI (FAT32)"
# El kernel entra UNA vez en la imagen EFI (como BOOTX64.EFI, que es la ruta
# que toda firmware prueba sin registrar nada). La copia con nombre propio vive
# en el sistema de archivos de la ISO, que no tiene el límite de la FAT.
# Un 20 % de margen cubre lo que gasta la propia tabla FAT: la primera versión
# ajustaba al byte y moría con "Disk full".
TAM_KB=$(( ( $(stat -c%s "$KERNEL") + $(stat -c%s "$INITRAMFS") ) * 12 / 10 / 1024 + 16384 ))
dd if=/dev/zero of="$TRABAJO/efiboot.img" bs=1K count="$TAM_KB" status=none
mkfs.vfat -n MIKEOS_EFI "$TRABAJO/efiboot.img" >/dev/null 2>&1

# mcopy (mtools) evita tener que montar nada, o sea que no hace falta root.
if command -v mcopy >/dev/null 2>&1; then
    mmd  -i "$TRABAJO/efiboot.img" ::/EFI ::/EFI/BOOT 2>/dev/null || true
    mcopy -i "$TRABAJO/efiboot.img" "$KERNEL"    ::/EFI/BOOT/BOOTX64.EFI
    mcopy -i "$TRABAJO/efiboot.img" "$INITRAMFS" ::/EFI/BOOT/initramfs.cpio.gz
    mcopy -i "$TRABAJO/efiboot.img" "$TRABAJO/raiz/EFI/BOOT/cmdline.txt" ::/EFI/BOOT/cmdline.txt
else
    err "falta mcopy (paquete mtools): sin él hay que montar la imagen como root."
    exit 1
fi
gris "  imagen EFI de $(du -h "$TRABAJO/efiboot.img" | cut -f1)"

# --- ISO híbrida --------------------------------------------------------------
# La imagen FAT va DENTRO del árbol de la ISO y se declara como arranque de
# El Torito con "-e". La primera versión usaba "-eltorito-alt-boot" con una
# partición añadida: esa es la receta de las ISO que arrancan también por BIOS
# y necesita una entrada primaria delante. Sin ella, la firmware no encontraba
# nada arrancable y se ponía a intentar arrancar por red
# ("failed to load Boot0002 ... Not Found", y detrás PXE, HTTP...).
#
# -isohybrid-gpt-basdat es lo que hace que el mismo archivo sirva grabado en un
# USB con dd, y no sólo como disco óptico.
paso "Construyendo la ISO"
mkdir -p "$TRABAJO/raiz/EFI/BOOT"
cp "$TRABAJO/efiboot.img" "$TRABAJO/raiz/EFI/BOOT/efiboot.img"
xorriso -as mkisofs \
    -iso-level 3 \
    -volid "MIKEOS" \
    -appid "MIKE OS" \
    -publisher "MIKE OS" \
    -J -joliet-long -rational-rock \
    -e EFI/BOOT/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$SALIDA" \
    "$TRABAJO/raiz" 2>&1 | grep -viE "^xorriso : (UPDATE|NOTE)|^libisofs: NOTE" | tail -4

[ -f "$SALIDA" ] || { err "no se generó la ISO"; exit 1; }

# El SHA256 se deja al lado: es lo que permite comprobar que lo descargado es
# lo que se publicó.
sha256sum "$SALIDA" | sed "s| .*| $(basename "$SALIDA")|" > "$SALIDA.sha256"

echo
verde "ISO lista: $SALIDA ($(du -h "$SALIDA" | cut -f1))"
gris "  SHA256: $(cut -d' ' -f1 "$SALIDA.sha256")"
echo
gris "Grabar en un USB:"
gris "  sudo dd if=$SALIDA of=/dev/sdX bs=4M status=progress oflag=sync"
