#!/bin/bash
# Arranca la ISO con firmware UEFI real y deja SSH abierto en el puerto 2244.
#
# Sirve para meterse dentro del sistema EN VIVO y mirar qué pasa. Las demás
# pruebas arrancan desde el disco, que es un camino distinto: el USB monta el
# sistema comprimido con una capa de escritura encima, y ahí han salido fallos
# que en el disco no existen.
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRABAJO="${TMPDIR:-/tmp}/mikeos-iso-vivo"
PUERTO="${MIKEOS_ISO_PORT:-2244}"
CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd

mkdir -p "$TRABAJO"
cp -f /usr/share/edk2/x64/OVMF_VARS.4m.fd "$TRABAJO/vars.fd"
chmod u+w "$TRABAJO/vars.fd"
# El socket de una ejecución anterior hace que QEMU se niegue a arrancar
# ("server=on" no puede crear uno que ya existe), y el fallo no dice nada.
rm -f "$TRABAJO/serie.log" "$TRABAJO/serie.sock"

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=(-enable-kvm -cpu host)
else
    # shellcheck disable=SC2054  # "tcg,thread=multi" es un solo argumento de QEMU
    ACCEL=(-accel tcg,thread=multi -cpu max)
fi

exec qemu-system-x86_64 \
    "${ACCEL[@]}" -m 4096 -smp 4 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$TRABAJO/vars.fd" \
    -drive "format=raw,file=$RAIZ/iso/mikeos.iso" \
    -netdev "user,id=n0,hostfwd=tcp::$PUERTO-:22" -device virtio-net-pci,netdev=n0 \
    -device virtio-vga -display none \
    -chardev "socket,id=serie,path=$TRABAJO/serie.sock,server=on,wait=off,logfile=$TRABAJO/serie.log" \
    -serial chardev:serie -no-reboot
