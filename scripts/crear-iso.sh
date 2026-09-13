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

# --- El sistema, comprimido ---------------------------------------------------
# Hasta ahora la ISO llevaba sólo el initramfs, y el initramfs excluye a
# propósito /usr/lib, /lib64, Hyprland y quickshell: 70 MB de los 689 que ocupa
# el sistema. Tenía sentido cuando el initramfs era un trampolín para llegar al
# disco, pero convierte en mentira lo que promete la ISO: "arranca en memoria y
# puedes probar el sistema entero sin tocar el disco". No estaba el escritorio.
#
# Ahora el sistema completo viaja en un squashfs dentro del medio. El initramfs
# lo monta de sólo lectura y le pone encima un tmpfs, así que se puede escribir
# sin tocar el USB y sin cargar 627 MB en RAM: sólo se lee lo que se usa.
paso "Comprimiendo el sistema"
if ! command -v mksquashfs >/dev/null 2>&1; then
    err "falta mksquashfs (paquete squashfs-tools)."
    exit 1
fi
[ -d "$RAIZ/rootfs" ] || { err "no hay rootfs. Ejecuta ./scripts/build.sh"; exit 1; }
# gzip y no zstd: el kernel de MIKE OS sólo trae CONFIG_SQUASHFS_ZLIB. Un
# squashfs que el kernel no sabe descomprimir es un USB que no arranca.
# -all-root: TODO pertenece a root dentro del squashfs.
#
# Sin esto el sistema en vivo no arranca, y de una forma que no se parece en
# nada a su causa. build.sh construye rootfs/ como un usuario normal, así que
# los archivos son del uid 1000. El initramfs y la imagen de disco se empaquetan
# con fakeroot, que los reescribe a root; mksquashfs no pasaba por ahí y se
# llevaba los dueños del equipo de construcción tal cual.
#
# Resultado: /bin/busybox quedaba "-rwsr-xr-x uid=1000", o sea setuid AL USUARIO
# 1000 en vez de a root. El sistema arrancaba como root, ejecutaba busybox, y el
# bit setuid le bajaba el euid a 1000. A partir de ahí nada con privilegios
# funcionaba: no se podía abrir /dev/tty1 (sin escritorio), syslogd no podía
# crear su socket, y el diagnóstico decía "uid=0(root) euid=1000(mike)".
#
# Es además un agujero: cualquiera que supiera el uid podría fabricar un medio
# con binarios setuid a un usuario concreto.
# Se empaqueta dentro de fakeroot, igual que el initramfs y la imagen de disco
# (ver el bloque equivalente en scripts/build.sh). Es la única forma de que los
# dueños salgan bien sin construir el sistema como root.
#
# "-all-root" no vale: pone TODO como root, incluido /home/mike, y entonces el
# escritorio no puede crear su propia configuración
# ("mkdir: can't create directory '/home/mike/.local/': Permission denied").
# Y sin nada, mksquashfs se lleva los dueños del equipo de construcción: el
# usuario 1000. Eso dejaba /bin/busybox como setuid AL USUARIO 1000 en vez de a
# root, así que el sistema arrancaba con euid=1000 y nada con privilegios
# funcionaba. Los dos extremos rompen, y de formas que no se parecen a su causa.
fakeroot -- env RAIZ="$RAIZ" DESTINO="$TRABAJO/sistema.squashfs" sh -c '
    set -e
    chown -R root:root "$RAIZ/rootfs"
    [ -d "$RAIZ/rootfs/home/mike" ] && chown -R 1000:1000 "$RAIZ/rootfs/home/mike"
    chmod 4755 "$RAIZ/rootfs/bin/busybox"
    chmod 4755 "$RAIZ/rootfs/usr/bin/m-sudo"
    # Igual que en build.sh: sin esto la pantalla de bloqueo del USB en vivo
    # no puede leer /etc/shadow y no acepta ninguna contraseña.
    chmod 4755 "$RAIZ/rootfs/usr/bin/m-autenticar"
    mksquashfs "$RAIZ/rootfs" "$DESTINO" \
        -comp gzip -b 1M -noappend -quiet \
        -e boot var/lib/mpm/repo
' || { err "falló mksquashfs"; exit 1; }
gris "  sistema.squashfs de $(du -h "$TRABAJO/sistema.squashfs" | cut -f1) (desde $(du -sh "$RAIZ/rootfs" | cut -f1))"

paso "Preparando el contenido"
# El kernel, el initramfs y el sistema van en el árbol de la ISO; la partición
# FAT lleva ÚNICAMENTE a GRUB.
#
# Es al revés de lo que parece intuitivo, y hay un motivo: cuando la firmware
# arranca por El Torito, la imagen FAT no queda expuesta como un dispositivo
# que GRUB pueda recorrer, así que "search --file" no encontraba el kernel aun
# estando ahí dentro ("no such device: /EFI/mikeos/vmlinuz.efi"). El sistema de
# archivos de la ISO sí lo ve. Además la FAT baja de 84 MB a menos de 3.
mkdir -p "$TRABAJO/raiz/EFI/BOOT" "$TRABAJO/raiz/EFI/mikeos" "$TRABAJO/raiz/mikeos"
cp "$KERNEL"    "$TRABAJO/raiz/EFI/mikeos/vmlinuz.efi"
cp "$INITRAMFS" "$TRABAJO/raiz/EFI/mikeos/initramfs.cpio.gz"
# El sistema va en el árbol de la ISO, no en la partición FAT: FAT32 no admite
# archivos de más de 4 GB y además comprime peor el espacio.
mv "$TRABAJO/sistema.squashfs" "$TRABAJO/raiz/mikeos/sistema.squashfs"

# El cmdline.txt ya no se escribe. Nunca sirvió de nada: ese archivo lo lee la
# firmware de la Raspberry Pi, no UEFI. Quien pasa la línea de órdenes ahora es
# GRUB, de forma explícita y por cada entrada del menú.

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
# La FAT lleva sólo GRUB (unos 2 MB). 16 MB dan de sobra y evitan tener que
# afinar el tamaño cada vez que GRUB engorde.
TAM_KB=16384
dd if=/dev/zero of="$TRABAJO/efiboot.img" bs=1K count="$TAM_KB" status=none
mkfs.vfat -n MIKEOS_EFI "$TRABAJO/efiboot.img" >/dev/null 2>&1

# --- GRUB ---------------------------------------------------------------
# El gestor de arranque va delante, y el kernel a pelo queda de respaldo.
#
# Con GRUB la línea de órdenes se pasa de forma explícita, así que el mismo
# medio puede ofrecer varias opciones (probar, modo seguro, sólo terminal,
# rescate). Sin él, el kernel sólo podía usar la que lleva compilada dentro y
# no había forma de elegir nada.
#
# Se sigue copiando el kernel como EFI/BOOT/BOOTX64.EFI: si GRUB se rompiera,
# el medio arranca igual. Un gestor de arranque es una pieza más que se puede
# romper, y no encender es el peor fallo posible.
if command -v grub-mkstandalone >/dev/null 2>&1; then
    paso "Construyendo GRUB"
    # grub-mkstandalone mete la configuración y los módulos DENTRO del propio
    # ejecutable EFI. Así no hay que copiar un árbol de módulos al medio ni
    # preocuparse de que GRUB encuentre sus piezas: es un solo archivo.
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="$TRABAJO/grubx64.efi" \
        --modules="part_gpt part_msdos fat iso9660 normal linux echo all_video search search_label search_fs_file configfile gfxterm gfxmenu serial terminal test sleep halt png video video_fb font smbios regexp" \
        "boot/grub/grub.cfg=$RAIZ/build/grub/grub.cfg.iso" \
        $(cd "$RAIZ/build/grub/tema" 2>/dev/null && for _t in *; do printf '%s ' "boot/grub/tema/$_t=$RAIZ/build/grub/tema/$_t"; done) 2>/dev/null \
        && gris "  grubx64.efi de $(du -h "$TRABAJO/grubx64.efi" | cut -f1)" \
        || { err "no se pudo construir GRUB"; exit 1; }
else
    err "falta grub-mkstandalone (paquete grub)."
    exit 1
fi

# mcopy (mtools) evita tener que montar nada, o sea que no hace falta root.
if command -v mcopy >/dev/null 2>&1; then
    mmd  -i "$TRABAJO/efiboot.img" ::/EFI ::/EFI/BOOT 2>/dev/null || true
    # Sólo GRUB. BOOTX64.EFI es la ruta que prueba toda firmware sin registrar
    # nada, así que es la que tiene que llevar al menú; el kernel lo carga
    # GRUB desde el sistema de archivos de la ISO.
    mcopy -i "$TRABAJO/efiboot.img" "$TRABAJO/grubx64.efi" ::/EFI/BOOT/BOOTX64.EFI
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
