#!/bin/bash
# Arranca MIKE OS con la ISO GUARDADA COMO ARCHIVO dentro de una partición,
# que es la forma en la que la mayoría de la gente la lleva en el USB.
#
# Por qué existe esta prueba
# --------------------------
# Todas las demás pruebas graban la ISO tal cual en el disco virtual, así que
# el medio ES un dispositivo de bloque y el arranque lo encuentra a la primera.
# Pero un USB con Ventoy (o Easy2Boot, o alguien que simplemente copió el
# archivo) no funciona así: la ISO es un archivo dentro de una partición, y el
# gestor de arranque la abre usando servicios de la firmware que dejan de
# existir en cuanto arranca Linux. A partir de ahí, para el sistema NO HAY
# ningún dispositivo que sea la ISO.
#
# Eso hacía que el USB llegara hasta el final del arranque -- menú, kernel,
# todos los mensajes -- y muriera en "NO ENCUENTRO EL SISTEMA EN NINGÚN
# DISPOSITIVO". Desde fuera parecía que la imagen estaba mal construida. Pasó
# en una Surface Laptop 4 y no salía en ninguna prueba porque ninguna prueba
# montaba la ISO como archivo.
#
# Lo que monta este script es justo esa forma: un disco GPT con una sola
# partición FAT32 que lleva GRUB, el kernel, el initramfs y mikeos.iso dentro
# como un archivo más.
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRABAJO="${TMPDIR:-/tmp}/mikeos-ventoy"
DISCO="$TRABAJO/usb.img"
CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
# SSH y monitor abiertos. Sin ellos, "arrancó" solo se puede deducir del puerto
# serie, y el serie deja de recibir en cuanto la consola pasa a la pantalla:
# justo el punto ciego que hizo que esto se diera por bueno sin estarlo.
PUERTO="${MIKEOS_VENTOY_PORT:-2245}"

err() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

[ -f "$RAIZ/iso/mikeos.iso" ] || { err "no hay ISO. Ejecuta ./scripts/crear-iso.sh"; exit 1; }
for t in mkfs.vfat mcopy mmd mdir sfdisk xorriso truncate qemu-system-x86_64; do
    command -v "$t" >/dev/null 2>&1 || { err "falta $t"; exit 1; }
done

mkdir -p "$TRABAJO"
rm -f "$TRABAJO/serie.log" "$TRABAJO/serie.sock" "$TRABAJO/monitor.sock" "$DISCO" "$TRABAJO/part.img"

# El tamaño: la ISO más el kernel y el initramfs, con holgura.
MB=$(( $(du -m "$RAIZ/iso/mikeos.iso" | cut -f1) + 400 ))
truncate -s "${MB}M" "$DISCO"

# Dos particiones, que es la forma exacta de un USB con Ventoy:
#
#   p1  grande, con las imágenes dentro como archivos    (exFAT / NTFS / FAT32)
#   p2  pequeña y FAT, la que arranca                    (VTOYEFI)
#
# La primera versión de esta prueba usaba una sola partición FAT32 para las dos
# cosas. Encontraba el fallo, pero no probaba lo mismo: el USB de verdad lleva
# las imágenes en exFAT, y ahí entra en juego una traducción que no es obvia
# --- blkid dice "ntfs"/"exfat" y el driver del kernel se llama "ntfs3" --- que
# con FAT32 no se ejercita.
#
# Se usa el mejor sistema de archivos que haya en el equipo de construcción, y
# se dice cuál, para que quede en el registro con qué se probó de verdad.
if command -v mkfs.exfat >/dev/null 2>&1; then
    FS_DATOS=exfat
elif command -v mkfs.ntfs >/dev/null 2>&1; then
    FS_DATOS=ntfs
else
    FS_DATOS=vfat
fi
echo "» Las imágenes van en una partición $FS_DATOS (como en un USB con Ventoy)"

# 200 MB, no 64: dentro van el kernel (23 MB) y el initramfs (52 MB), y con 64
# el formateo terminaba en un "Disk full" sin más explicación.
ESP_MB=200
DATOS_MB=$(( MB - ESP_MB - 2 ))
sfdisk --quiet --label gpt "$DISCO" >/dev/null 2>&1 <<PARTICIONES
start=2048, size=${DATOS_MB}M, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="VENTOY_DATOS"
size=${ESP_MB}M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="VTOYEFI"
PARTICIONES

# mkfs no sabe de tablas de particiones, así que cada partición se formatea en
# un archivo suelto y luego se pega en su sitio con dd.
DATOS="$TRABAJO/datos.img"
PART="$TRABAJO/esp.img"
rm -f "$DATOS" "$PART"
truncate -s "${DATOS_MB}M" "$DATOS"
truncate -s "${ESP_MB}M" "$PART"
case "$FS_DATOS" in
    exfat) mkfs.exfat -n VENTOY "$DATOS" >/dev/null 2>&1 ;;
    ntfs)  mkfs.ntfs  -Q -F -L VENTOY "$DATOS" >/dev/null 2>&1 ;;
    vfat)  mkfs.vfat -F 32 -n VENTOY "$DATOS" >/dev/null 2>&1 ;;
esac || { err "no se pudo formatear la partición de datos"; exit 1; }
mkfs.vfat -F 32 -n VTOYEFI "$PART" >/dev/null 2>&1 || { err "no se pudo formatear la ESP"; exit 1; }

# GRUB, el kernel y el initramfs se sacan de la propia ISO: así se prueba
# exactamente lo que se publica, no una copia paralela que podría diferir.
EXTRA="$TRABAJO/desde-iso"
# xorriso extrae con los permisos de la ISO, que es de sólo lectura: sin
# devolver el permiso de escritura, el "rm -rf" de la siguiente ejecución
# falla y la prueba se queda con la extracción de la vez anterior.
[ -d "$EXTRA" ] && chmod -R u+w "$EXTRA"
rm -rf "$EXTRA"; mkdir -p "$EXTRA"
xorriso -osirrox on -indev "$RAIZ/iso/mikeos.iso" \
        -extract /EFI "$EXTRA/EFI" >/dev/null 2>&1 \
    || { err "no se pudo sacar /EFI de la ISO"; exit 1; }

mmd -i "$PART" ::/EFI ::/EFI/BOOT ::/EFI/mikeos >/dev/null 2>&1 || true
mcopy -i "$PART" "$EXTRA/EFI/BOOT/BOOTX64.EFI"           ::/EFI/BOOT/BOOTX64.EFI 2>/dev/null \
  || mcopy -i "$PART" "$EXTRA/EFI/BOOT/efiboot.img"      ::/EFI/BOOT/efiboot.img
mcopy -i "$PART" "$EXTRA/EFI/mikeos/vmlinuz.efi"         ::/EFI/mikeos/vmlinuz.efi
mcopy -i "$PART" "$EXTRA/EFI/mikeos/initramfs.cpio.gz"   ::/EFI/mikeos/initramfs.cpio.gz

# Y aquí está lo que se prueba: la ISO entera, como un archivo cualquiera,
# en la partición de datos. En una carpeta y no en la raíz, porque es donde la
# deja mucha gente y obliga a que la búsqueda baje niveles.
#
# En exFAT y NTFS no vale mcopy (es de mtools, sólo FAT): hay que montar. Es
# el único punto de la prueba que necesita permisos de root, y sólo para
# preparar el USB falso; el arranque no los usa.
copiar_iso_a_datos() {
    _m="$TRABAJO/montaje-datos"
    mkdir -p "$_m"
    if [ "$FS_DATOS" = "vfat" ]; then
        mmd -i "$DATOS" ::/imagenes >/dev/null 2>&1 || true
        mcopy -i "$DATOS" "$RAIZ/iso/mikeos.iso" ::/imagenes/mikeos.iso
        return
    fi
    sudo mount -o loop "$DATOS" "$_m" || { err "no se pudo montar la partición de datos"; exit 1; }
    sudo mkdir -p "$_m/imagenes"
    sudo cp "$RAIZ/iso/mikeos.iso" "$_m/imagenes/mikeos.iso"
    sudo sync
    sudo umount "$_m"
}
copiar_iso_a_datos

# Si la ISO no trajo un BOOTX64.EFI suelto (va dentro de efiboot.img), se saca
# de ahí para que la firmware lo encuentre en la ruta que prueba siempre.
if ! mdir -i "$PART" ::/EFI/BOOT/BOOTX64.EFI >/dev/null 2>&1; then
    mcopy -i "$PART" -m "::/EFI/BOOT/efiboot.img" "$TRABAJO/efiboot.img" 2>/dev/null || true
    if [ -f "$TRABAJO/efiboot.img" ]; then
        mcopy -i "$TRABAJO/efiboot.img" "::/EFI/BOOT/BOOTX64.EFI" "$TRABAJO/BOOTX64.EFI" 2>/dev/null || true
        [ -f "$TRABAJO/BOOTX64.EFI" ] && mcopy -i "$PART" "$TRABAJO/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
    fi
fi

# Cada partición a su sitio: los datos en el MiB 1, la ESP justo detrás.
dd if="$DATOS" of="$DISCO" bs=1M seek=1 conv=notrunc status=none
dd if="$PART"  of="$DISCO" bs=1M seek="$(( 1 + DATOS_MB ))" conv=notrunc status=none

cp -f /usr/share/edk2/x64/OVMF_VARS.4m.fd "$TRABAJO/vars.fd"
chmod u+w "$TRABAJO/vars.fd"

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=(-enable-kvm -cpu host)
else
    # shellcheck disable=SC2054  # "tcg,thread=multi" es un solo argumento de QEMU
    ACCEL=(-accel tcg,thread=multi -cpu max)
fi

# El disco va por USB, no por SATA. No es un detalle: el camino de USB tarda
# más en enumerar y es el que usa un pendrive de verdad, que es donde falló.
exec qemu-system-x86_64 \
    "${ACCEL[@]}" -m 4096 -smp 4 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$TRABAJO/vars.fd" \
    -device qemu-xhci,id=xhci \
    -drive "if=none,id=usb0,format=raw,file=$DISCO" \
    -device usb-storage,bus=xhci.0,drive=usb0 \
    -netdev "user,id=n0,hostfwd=tcp::$PUERTO-:22" -device virtio-net-pci,netdev=n0 \
    -device virtio-vga -display none \
    -monitor "unix:$TRABAJO/monitor.sock,server,nowait" \
    -chardev "socket,id=serie,path=$TRABAJO/serie.sock,server=on,wait=off,logfile=$TRABAJO/serie.log" \
    -serial chardev:serie -no-reboot
