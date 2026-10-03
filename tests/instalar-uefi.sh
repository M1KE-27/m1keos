#!/bin/bash
# Instalar MIKE OS de punta a punta con firmware UEFI real, y arrancar lo
# instalado.
#
# Por qué existe
# --------------
# Ninguna prueba instalaba. Y el instalador llevaba desde el principio sin
# poder registrarse en la NVRAM de la UEFI (efivarfs iba como módulo en un
# kernel que no carga módulos), sin que nada lo dijera: la nota decía
# "arrancará por EFI/BOOT/BOOTX64.EFI", que al lado de Windows es falso,
# porque la firmware sigue SU lista y en ella va Windows primero.
#
# Esto hace lo que hace una persona:
#   1. Arranca el USB (la ISO) con OVMF y un disco vacío.
#   2. Instala en el disco, sin preguntas.
#   3. Apaga, quita el USB, y vuelve a encender con la MISMA NVRAM.
#   4. Comprueba que arrancó desde la entrada "MIKE OS" de la UEFI, a través
#      de GRUB, con el kernel y el idioma que tocan.
#
# Necesita una imagen construida con la clave de desarrollo
# (MIKEOS_SSH_AUTHORIZED_KEYS_FILE) y la ISO hecha con ./scripts/crear-iso.sh.
#
#   ./tests/instalar-uefi.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="$RAIZ/iso/mikeos.iso"
CLAVE="${MIKEOS_DEV_KEY:-$HOME/.ssh/mikeos_dev}"
PUERTO="${MIKEOS_INST_PORT:-2266}"
CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
VARS0=/usr/share/edk2/x64/OVMF_VARS.4m.fd
T="${MIKEOS_TEST_DIR:-${TMPDIR:-/tmp}/mikeos-instalar}"

verde(){ printf '\033[32m%s\033[0m\n' "$*"; }
rojo(){ printf '\033[31m%s\033[0m\n' "$*"; }
paso(){ printf '\033[1m»\033[0m %s\n' "$*"; }
vm(){ ssh -p "$PUERTO" -i "$CLAVE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR -o ConnectTimeout=5 mike@localhost \
          "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; $*" 2>/dev/null; }
esperar_ssh(){ for _ in $(seq 1 60); do vm true && return 0; sleep 5; done; return 1; }

[ -f "$ISO" ] || { rojo "No hay ISO: ./scripts/crear-iso.sh"; exit 2; }
[ -f "$CODE" ] || { rojo "Falta OVMF (edk2-ovmf)."; exit 2; }
if ss -ltn 2>/dev/null | grep -q ":$PUERTO "; then rojo "El puerto $PUERTO ya está en uso."; exit 2; fi

mkdir -p "$T"; rm -f "$T"/disco.img "$T"/vars.fd "$T"/serie*.log
truncate -s 24G "$T/disco.img"
cp "$VARS0" "$T/vars.fd"; chmod u+w "$T/vars.fd"

qemu_arranque(){ # qemu_arranque <log> [más opciones]
    local log="$1"; shift
    qemu-system-x86_64 -enable-kvm -cpu host -m 4096 -smp 4 \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$T/vars.fd" \
        -drive "if=virtio,format=raw,file=$T/disco.img" \
        "$@" \
        -netdev "user,id=n0,hostfwd=tcp::$PUERTO-:22" -device virtio-net-pci,netdev=n0 \
        -device virtio-vga -display none -serial "file:$log" -no-reboot \
        >"$T/qemu.log" 2>&1 &
    QPID=$!
}
MAL=0
ok(){ verde "  ✓ $1"; }
no(){ rojo "  ✗ $1"; MAL=1; }

paso "1. Arrancando el USB con un disco vacío"
qemu_arranque "$T/serie1.log" -drive "format=raw,media=cdrom,file=$ISO,readonly=on"
esperar_ssh || { rojo "El USB no llegó a contestar."; kill $QPID 2>/dev/null; exit 1; }
DISCO="$(vm 'for d in /dev/vd?; do [ -b "$d" ] && echo $d && break; done')"
[ -n "$DISCO" ] && ok "sistema en vivo arriba; disco de destino $DISCO" || { no "no veo el disco virtio"; kill $QPID; exit 1; }
vm 'mount | grep -q efivarfs' && ok "efivarfs montado en el sistema en vivo" || no "efivarfs NO está montado"

paso "2. Instalando (sin preguntas)"
vm "echo 'prueba1234' | m-sudo m-install --disco $DISCO --fs btrfs --equipo prueba-uefi --idioma en --clave-por-entrada --si" > "$T/instalar.log" 2>&1
tail -5 "$T/instalar.log" | sed 's/^/    /'
grep -q "registrado en la UEFI como primera opción" "$T/instalar.log" \
    && ok "el instalador se registró en la UEFI" || no "el instalador NO se registró en la UEFI"
NVRAM="$(vm 'm-sudo efibootmgr')"
printf '%s\n' "$NVRAM" | sed 's/^/    /'
_primera="$(printf '%s\n' "$NVRAM" | sed -n 's/^BootOrder: \([0-9A-Fa-f]*\).*/\1/p')"
_linea="$(printf '%s\n' "$NVRAM" | grep "^Boot$_primera")"
case "$_linea" in
    *"MIKE OS (kernel)"*) no "la primera del orden es la de respaldo, no GRUB" ;;
    *"MIKE OS"*)          ok "\"MIKE OS\" (GRUB) es la primera del orden de arranque" ;;
    *)                    no "la primera del orden no es MIKE OS: $_linea" ;;
esac
printf '%s\n' "$NVRAM" | grep -q "MIKE OS (kernel)" && ok "y el kernel como respaldo" || no "falta la entrada de respaldo"
vm 'm-sudo poweroff' >/dev/null 2>&1; sleep 15; kill $QPID 2>/dev/null; wait $QPID 2>/dev/null

paso "3. Arrancando SÓLO desde el disco, con la misma NVRAM"
qemu_arranque "$T/serie2.log"
esperar_ssh || { rojo "Lo instalado no llegó a contestar."; tail -20 "$T/serie2.log"; kill $QPID; exit 1; }
ok "lo instalado arranca y contesta"
_bc="$(vm 'm-sudo efibootmgr' | sed -n 's/^BootCurrent: //p')"
vm 'm-sudo efibootmgr' | grep -q "^Boot$_bc\* MIKE OS" && ok "arrancó por la entrada \"MIKE OS\" de la UEFI (Boot$_bc)" || no "BootCurrent=$_bc no es MIKE OS"
grep -aq "GNU GRUB\|Booting \`MIKE OS" "$T/serie2.log" && ok "pasando por GRUB" || no "no se ve GRUB en el arranque"
[ "$(vm 'uname -r')" = "$(sed -n 's/^KERNEL_TAG="v\(.*\)"/\1/p' "$RAIZ/scripts/build.sh")-mikeos" ] \
    && ok "kernel $(vm 'uname -r')" || no "kernel inesperado: $(vm 'uname -r')"
[ "$(vm 'm-idioma')" = "en" ] && ok "en el idioma elegido al instalar (en)" || no "idioma: $(vm 'm-idioma')"
vm 'mount | grep -q " / type btrfs"' && ok "raíz en btrfs" || no "la raíz no es btrfs"
vm 'mount | grep -q " /home "' && ok "/home montado (subvolumen @home)" || no "/home no está montado"
vm 'grep -q "vmlinuz-anterior.efi" /boot/efi/EFI/mikeos/grub-disco.cfg' && ok "el menú lleva la entrada del kernel anterior" || no "falta la entrada del kernel anterior"
vm 'm-sudo poweroff' >/dev/null 2>&1; sleep 10; kill $QPID 2>/dev/null; wait $QPID 2>/dev/null

echo
[ "$MAL" = 0 ] && verde "Instalar y arrancar lo instalado: todo bien." || rojo "Hay fallos (arriba). Registros en $T"
exit $MAL
