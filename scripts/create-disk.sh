#!/bin/bash
# ==============================================================================
# MIKE OS - Persistent Disk Generator (Fase 1: Persistencia)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS_DIR="$PROJECT_ROOT/rootfs"
ISO_DIR="$PROJECT_ROOT/iso"
DISK_IMAGE="$ISO_DIR/mikeos.img"
# El perfil base (Hyprland/Mesa/Qt) ocupa ~850MB, pero con el catálogo de
# recetas mpm (Firefox, Node, Go, Python...) instalando paquetes reales bajo
# demanda, 1900M se llenaba tras un puñado de instalaciones. Es un archivo
# sparse: solo ocupa disco real conforme se usa, así que dar margen aquí no
# cuesta nada hasta que realmente se llena.
DISK_SIZE="10G"

mkdir -p "$ISO_DIR"

if [ ! -d "$ROOTFS_DIR" ]; then
    echo "ERROR: RootFS no existe. Ejecuta ./scripts/build.sh primero." >&2
    exit 1
fi

echo "=== Creando imagen de disco ext4 persistente: $DISK_IMAGE ($DISK_SIZE) ==="
rm -f "$DISK_IMAGE"

# mke2fs -d preserva el UID/GID del filesystem host tal cual. Como el build
# corre como usuario normal (no root), TODO en la imagen -- incluido
# /etc/shadow -- quedaba con el propietario de quien compila, no root. Eso
# volvía inútil cualquier "chmod 600": el propio usuario dueño del archivo
# puede reabrirlo en modo escritura sin ser root. fakeroot finge la
# propiedad root:root solo dentro de esta sesión (no toca el filesystem
# real del host) para que mke2fs empaquete los permisos correctos.
if ! command -v fakeroot >/dev/null 2>&1; then
    echo "ERROR: fakeroot no está instalado; es necesario para empaquetar la imagen con la propiedad root correcta." >&2
    exit 1
fi

fakeroot -- env ROOTFS_DIR="$ROOTFS_DIR" DISK_IMAGE="$DISK_IMAGE" DISK_SIZE="$DISK_SIZE" sh -c '
    set -e
    chown -R root:root "$ROOTFS_DIR"
    [ -d "$ROOTFS_DIR/home/mike" ] && chown -R 1000:1000 "$ROOTFS_DIR/home/mike"
    chmod 4755 "$ROOTFS_DIR/bin/busybox"
    chmod 4755 "$ROOTFS_DIR/usr/bin/m-sudo"
    mke2fs -t ext4 -L "MIKEOS_ROOT" -d "$ROOTFS_DIR" -m 1 "$DISK_IMAGE" "$DISK_SIZE" >/dev/null
'

echo "================================================================"
echo " ¡Disco persistente de MIKE OS creado con éxito!"
echo " Archivo:  $DISK_IMAGE"
echo " Tamaño:   $(du -h "$DISK_IMAGE" | cut -f1)"
echo " Etiqueta: MIKEOS_ROOT"
echo "================================================================"
