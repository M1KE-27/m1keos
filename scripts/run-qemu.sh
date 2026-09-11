#!/bin/bash
# MIKE OS - lanzador QEMU con perfiles de hardware/virtualización
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL="$PROJECT_ROOT/kernel/arch/x86/boot/bzImage"
INITRAMFS="$PROJECT_ROOT/iso/initramfs.cpio.gz"
DISK_IMG="$PROJECT_ROOT/iso/mikeos.img"

[ -f "$KERNEL" ] || { echo "ERROR: Kernel no encontrado en $KERNEL." >&2; exit 1; }

BOOT_MODE=disk
DISK_BUS=virtio
NET_MODEL=virtio
VGA_MODEL=virtio
MEM_SIZE=512M
CPU_COUNT=4
EXTRA_CMDLINE=""
HEADLESS=1
NO_KVM=0
NO_GL=0
SSH_PORT=2222
NO_SSH=0
GUI_MODE=0
AUTO_DESKTOP=0
VIDEO_SIZE=1920x1080
VIDEO_REFRESH=75
DISPLAY_FLAGS=(-nographic)

usage() {
    cat <<EOF
Uso: $0 [opciones]
  -i, --initramfs       Arranque en RAM
  -r, --recovery        Shell de rescate
  -g, --gui             Ventana gráfica con MKShell (arranca en terminal, no en Hyprland)
      --desktop         Combinado con --gui, auto-lanza MIKE Desktop (Hyprland) al arrancar
      --resolution WxH  Resolución preferida del monitor (defecto: 1920x1080)
      --refresh HZ      Frecuencia preferida (defecto: 75; usa la anunciada si no existe)
      --disk-bus BUS    virtio (defecto), sata o scsi
      --net-model NIC   virtio (defecto), e1000, rtl8139 o vmxnet3
      --vga MODE        virtio (defecto), std, qxl, vmware o none
      --memory SIZE     RAM QEMU (ej. 1G, 2048M)
      --cpus N          CPUs virtuales
      --no-kvm          Forzar TCG aunque exista /dev/kvm
      --no-gl           Desactiva aceleración 3D virgl (usa Mesa software)
      --headless        Consola serie sin ventana
      --ssh-port N      Puerto host para SSH (defecto: 2222)
      --no-ssh          Desactiva el port-forward SSH del host
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -i|--initramfs) BOOT_MODE=initramfs ;;
        -r|--recovery) EXTRA_CMDLINE="$EXTRA_CMDLINE mikeos_recovery=1" ;;
        -g|--gui|--1080p|--fhd)
            HEADLESS=0
            GUI_MODE=1
            # Se reparte según lo que tenga el anfitrión, no una cifra fija:
            # la mitad de la memoria (con un tope de 12 GB para no dejar al
            # anfitrión sin margen) y todos los hilos menos dos, que hacen
            # falta para el propio QEMU y para el escritorio de quien mira.
            # Con 6 GB, una máquina virtual con Java y un juego dentro se
            # pasa la vida intercambiando memoria.
            _ram_host_mb="$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 4096)"
            _ram_vm=$(( _ram_host_mb / 2 ))
            [ "$_ram_vm" -gt 12288 ] && _ram_vm=12288
            [ "$_ram_vm" -lt 2048 ] && _ram_vm=2048
            MEM_SIZE="${_ram_vm}M"
            _hilos="$(nproc 2>/dev/null || echo 4)"
            CPU_COUNT=$(( _hilos > 3 ? _hilos - 2 : 1 ))
            ;;
        --desktop) AUTO_DESKTOP=1 ;;
        --no-gl) NO_GL=1 ;;
        --resolution) VIDEO_SIZE="${2:?Falta la resolución (ej. 1920x1080)}"; shift ;;
        --refresh) VIDEO_REFRESH="${2:?Falta la frecuencia (ej. 75)}"; shift ;;
        --disk-bus) DISK_BUS="${2:?Falta el bus de disco}"; shift ;;
        --net-model) NET_MODEL="${2:?Falta el modelo de red}"; shift ;;
        --vga) VGA_MODEL="${2:?Falta el modelo VGA}"; shift ;;
        --memory) MEM_SIZE="${2:?Falta la cantidad de memoria}"; shift ;;
        --cpus) CPU_COUNT="${2:?Falta el número de CPUs}"; shift ;;
        --no-kvm) NO_KVM=1 ;;
        --headless) HEADLESS=1 ;;
        --ssh-port) SSH_PORT="${2:?Falta el puerto SSH}"; shift ;;
        --no-ssh) NO_SSH=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: opción desconocida: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if ! [[ "$VIDEO_SIZE" =~ ^[0-9]+x[0-9]+$ ]]; then
    echo "ERROR: --resolution debe tener formato WxH, por ejemplo 1920x1080." >&2
    exit 2
fi
if ! [[ "$VIDEO_REFRESH" =~ ^[0-9]+$ ]] || [ "$VIDEO_REFRESH" -lt 1 ]; then
    echo "ERROR: --refresh debe ser un número positivo." >&2
    exit 2
fi
if [ "$GUI_MODE" -eq 1 ]; then
    # video=WxH@Hz siempre se pasa (afecta también a la consola en modo
    # ventana); mikeos_gui=1 solo se añade si se pidió --desktop, que es lo
    # único que hace que /etc/sv/console/run auto-lance Hyprland en vez de
    # dejar el prompt de MKShell en pantalla.
    EXTRA_CMDLINE="$EXTRA_CMDLINE video=${VIDEO_SIZE}@${VIDEO_REFRESH}"
    [ "$AUTO_DESKTOP" -eq 1 ] && EXTRA_CMDLINE="$EXTRA_CMDLINE mikeos_gui=1"
fi

case "$DISK_BUS" in
    virtio) ROOT_DISK=vda; DISK_FLAGS=(-drive "file=$DISK_IMG,format=raw,if=virtio,cache=writeback,aio=threads") ;;
    sata|ide) ROOT_DISK=sda; DISK_FLAGS=(-drive "file=$DISK_IMG,format=raw,if=ide,cache=writeback") ;;
    scsi) ROOT_DISK=sda; DISK_FLAGS=(-device virtio-scsi-pci,id=scsi -drive "file=$DISK_IMG,format=raw,if=none,id=disk,cache=writeback" -device scsi-hd,drive=disk) ;;
    *) echo "ERROR: --disk-bus debe ser virtio, sata o scsi." >&2; exit 2 ;;
esac

case "$NET_MODEL" in
    virtio) NET_DEVICE=virtio-net-pci ;;
    e1000) NET_DEVICE=e1000 ;;
    rtl8139) NET_DEVICE=rtl8139 ;;
    vmxnet3) NET_DEVICE=vmxnet3 ;;
    *) echo "ERROR: --net-model debe ser virtio, e1000, rtl8139 o vmxnet3." >&2; exit 2 ;;
esac
[ "$NET_MODEL" = rtl8139 ] && NET_DEVICE=rtl8139

if [ "$NO_KVM" -eq 0 ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL_FLAGS=(-enable-kvm -cpu host)
else
    echo "Aviso: KVM no disponible o desactivado; usando TCG multihilo."
    ACCEL_FLAGS=(-accel tcg,thread=multi -cpu max)
fi

if [ "$HEADLESS" -eq 0 ]; then
    GL_SUFFIX="off"
    case "$VGA_MODEL" in
        virtio)
            if [ "$NO_GL" -eq 0 ]; then
                # Venus expone Vulkan real dentro de la máquina virtual, no
                # sólo OpenGL. Es lo que hace falta para DXVK y VKD3D-Proton,
                # o sea para que DirectX 11 y 12 funcionen bajo Wine, y lo que
                # separa a Minecraft de ir a trompicones. Necesita recursos
                # "blob" y memoria compartida con el anfitrión.
                #
                # No todas las versiones de QEMU lo traen: si no está, se cae
                # a virgl a secas, que sigue dando OpenGL.
                if qemu-system-x86_64 -device virtio-vga-gl,help 2>&1 | grep -q "venus="; then
                    DISPLAY_FLAGS=(-device virtio-vga-gl,max_outputs=1,venus=on,blob=true,hostmem=4G)
                    # Venus mapea memoria del anfitrión en la máquina virtual:
                    # sin memory-backend-memfd compartido, el mapeo falla.
                    DISPLAY_FLAGS+=(-object memory-backend-memfd,id=mem1,size="$MEM_SIZE",share=on
                                    -machine memory-backend=mem1)
                else
                    DISPLAY_FLAGS=(-device virtio-vga-gl,max_outputs=1)
                fi
                GL_SUFFIX="on"
            else
                DISPLAY_FLAGS=(-device virtio-vga,max_outputs=1)
            fi
            ;;
        std) DISPLAY_FLAGS=(-vga std) ;;
        qxl) DISPLAY_FLAGS=(-vga qxl) ;;
        vmware) DISPLAY_FLAGS=(-vga vmware) ;;
        none) DISPLAY_FLAGS=(-display none) ;;
        *) echo "ERROR: --vga debe ser virtio, std, qxl, vmware o none." >&2; exit 2 ;;
    esac
    # gl=on solo es válido con virtio-vga-gl; el resto de modelos no exponen
    # un contexto GL a QEMU y deben quedarse en gl=off.
    [ "$VGA_MODEL" = none ] || DISPLAY_FLAGS+=("-display" "gtk,gl=${GL_SUFFIX},grab-on-hover=on,show-menubar=off" "-device" qemu-xhci "-device" usb-tablet)
fi

if [ "$BOOT_MODE" = disk ] && [ ! -f "$DISK_IMG" ]; then
    echo "Generando disco persistente..."
    "$PROJECT_ROOT/scripts/create-disk.sh"
fi

if command -v ss >/dev/null 2>&1 && [ "$NO_SSH" -eq 0 ]; then
    _candidate="$SSH_PORT"
    while ss -ltn 2>/dev/null | grep -Eq ":${_candidate}[[:space:]]" && [ "$_candidate" -lt 2300 ]; do
        _candidate=$((_candidate + 1))
    done
    if [ "$_candidate" != "$SSH_PORT" ]; then
        echo "Aviso: puerto $SSH_PORT ocupado; SSH de MIKE OS usará $_candidate."
        SSH_PORT="$_candidate"
    fi
fi
if [ "$NO_SSH" -eq 1 ]; then
    NET_FLAGS=(-netdev user,id=net0 -device "$NET_DEVICE,netdev=net0")
else
    NET_FLAGS=(-netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22 -device "$NET_DEVICE,netdev=net0")
fi
if [ "$BOOT_MODE" = disk ]; then
    if [ "$HEADLESS" -eq 1 ]; then
        CMDLINE="root=/dev/$ROOT_DISK rw rootwait console=ttyS0 panic=1 $EXTRA_CMDLINE"
    else
        CMDLINE="root=/dev/$ROOT_DISK rw rootwait console=tty0 console=ttyS0 panic=1 $EXTRA_CMDLINE"
    fi
else
    if [ "$HEADLESS" -eq 1 ]; then
        CMDLINE="root=/dev/ram0 rw console=ttyS0 panic=1 $EXTRA_CMDLINE"
    else
        CMDLINE="root=/dev/ram0 rw console=tty0 console=ttyS0 panic=1 $EXTRA_CMDLINE"
    fi
fi
# Tarjeta de sonido virtual. Sin ella el invitado no ve ningún dispositivo de
# audio y no hay volumen que leer ni probar. La salida va a "none": interesa
# que exista el dispositivo, no oírlo desde el anfitrión.
AUDIO_FLAGS=(-audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0)

COMMON_FLAGS=("${ACCEL_FLAGS[@]}" "${AUDIO_FLAGS[@]}" -kernel "$KERNEL" -initrd "$INITRAMFS" -append "$CMDLINE" "${NET_FLAGS[@]}" "${DISPLAY_FLAGS[@]}" -serial mon:stdio -smp "$CPU_COUNT" -m "$MEM_SIZE" -no-reboot)

echo "MIKE OS | disco=$DISK_BUS red=$NET_MODEL video=$VGA_MODEL cpu=$CPU_COUNT ram=$MEM_SIZE"
if [ "$BOOT_MODE" = disk ]; then
    exec qemu-system-x86_64 "${COMMON_FLAGS[@]}" "${DISK_FLAGS[@]}"
else
    # En initramfs no hace falta adjuntar disco; conservar el mismo perfil de
    # CPU/red permite reproducir fallos de VM en modo recovery.
    exec qemu-system-x86_64 "${COMMON_FLAGS[@]}"
fi
