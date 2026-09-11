#!/bin/bash
# ==============================================================================
# probar-arranque-uefi.sh - ¿arranca MIKE OS por sí solo?
#
# Todas las pruebas anteriores usan QEMU con "-kernel bzImage -initrd ...", o
# sea que QEMU le da el kernel en la mano y se salta el arranque entero. Eso no
# demuestra nada sobre un portátil de verdad.
#
# Esto es lo contrario: firmware UEFI real (OVMF), un disco con tabla GPT y su
# partición EFI, y nadie que le pase nada al kernel. Si arranca aquí, arranca
# en la Surface.
#
#   ./tests/probar-arranque-uefi.sh            disco GPT + ESP (como m-install)
#   ./tests/probar-arranque-uefi.sh --iso      la ISO, como un USB
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRABAJO="${MIKEOS_TEST_DIR:-${TMPDIR:-/tmp}/mikeos-uefi}"
KERNEL="$RAIZ/kernel/arch/x86/boot/bzImage"
INITRAMFS="$RAIZ/iso/initramfs.cpio.gz"
ISO="$RAIZ/iso/mikeos.iso"
CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
VARS_ORIG=/usr/share/edk2/x64/OVMF_VARS.4m.fd

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }

MODO=disco
[ "${1:-}" = "--iso" ] && MODO=iso

[ -f "$CODE" ] || { rojo "Falta OVMF ($CODE). Instala edk2-ovmf."; exit 1; }
mkdir -p "$TRABAJO"
SERIE="$TRABAJO/serie.log"
rm -f "$SERIE"
cp "$VARS_ORIG" "$TRABAJO/OVMF_VARS.fd"
chmod u+w "$TRABAJO/OVMF_VARS.fd"

if [ "$MODO" = disco ]; then
    [ -f "$KERNEL" ] || { rojo "No hay kernel."; exit 1; }
    paso "Creando un disco GPT con su partición EFI (igual que m-install)"
    DISCO="$TRABAJO/disco.img"
    PART="$TRABAJO/part.img"
    rm -f "$DISCO" "$PART"
    truncate -s 300M "$DISCO"
    printf ',,U,*\n' | sfdisk --quiet --wipe always --label gpt "$DISCO" >/dev/null
    OFF="$(sfdisk -J "$DISCO" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][0]["start"])')"
    SZ="$(sfdisk -J "$DISCO" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][0]["size"])')"
    gris "  ESP en el sector $OFF, $SZ sectores"
    truncate -s "$((SZ * 512))" "$PART"
    mkfs.vfat -n MIKEOS_EFI "$PART" >/dev/null 2>&1
    mmd -i "$PART" ::/EFI >/dev/null 2>&1
    mmd -i "$PART" ::/EFI/BOOT >/dev/null 2>&1
    mcopy -i "$PART" "$KERNEL" ::/EFI/BOOT/BOOTX64.EFI
    [ -f "$INITRAMFS" ] && mcopy -i "$PART" "$INITRAMFS" ::/EFI/BOOT/initramfs.cpio.gz
    dd if="$PART" of="$DISCO" bs=512 seek="$OFF" conv=notrunc status=none
    verde "  disco listo"
    MEDIO=(-drive "format=raw,file=$DISCO")
else
    [ -f "$ISO" ] || { rojo "No hay ISO. Ejecuta ./scripts/crear-iso.sh"; exit 1; }
    paso "Arrancando la ISO como si fuera un USB"
    MEDIO=(-drive "format=raw,file=$ISO")
fi

paso "Arrancando con firmware UEFI real, sin pasarle el kernel"
qemu-system-x86_64 \
    -accel tcg,thread=multi -cpu max -m 2048 -smp 4 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$TRABAJO/OVMF_VARS.fd" \
    "${MEDIO[@]}" \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -device virtio-vga -display none \
    -serial "file:$SERIE" -no-reboot \
    > "$TRABAJO/qemu.log" 2>&1 &
QPID=$!

printf "Esperando"
ARRANCO=0
for _ in $(seq 1 60); do
    if grep -qaiE "Linux version" "$SERIE" 2>/dev/null; then ARRANCO=1; break; fi
    printf "."
    sleep 5
done
echo

if [ "$ARRANCO" -eq 1 ]; then
    verde "El kernel ha arrancado solo."
    echo
    tr -d '\0' < "$SERIE" | grep -aiE "Linux version|Command line|Freeing|runit|MIKE OS" | head -8 | sed 's/^/    /'
    # Que arranque el kernel no basta: hay que llegar a runit, que es cuando el
    # sistema está realmente en pie y no en un pánico bonito.
    printf "Esperando a runit"
    LLEGO=0
    for _ in $(seq 1 40); do
        if grep -qai "runit" "$SERIE" 2>/dev/null; then LLEGO=1; break; fi
        printf "."
        sleep 5
    done
    echo
    if [ "$LLEGO" -eq 1 ]; then
        verde "Y el sistema llega a runit: arranca de verdad."
        RC=0
    else
        rojo "El kernel arranca pero no llega a runit."
        tr -d '\0' < "$SERIE" | tail -12 | sed 's/^/    /'
        RC=1
    fi
else
    rojo "No arranca: la firmware no llegó a ejecutar el kernel."
    echo
    tr -d '\0' < "$SERIE" | grep -aiE "failed to load|Not Found|PXE" | head -4 | sed 's/^/    /'
    RC=1
fi

kill -9 "$QPID" 2>/dev/null
gris "Registro completo: $SERIE"
exit "$RC"
