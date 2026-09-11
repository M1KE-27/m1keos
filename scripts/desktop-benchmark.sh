#!/bin/bash
# ==============================================================================
# MIKE OS - Desktop Benchmark Runner
# Measures live Wayland, Hyprland, Quickshell, MCore and Kernel telemetry.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KERNEL="$PROJECT_ROOT/kernel/arch/x86/boot/bzImage"
INITRAMFS="$PROJECT_ROOT/iso/initramfs.cpio.gz"
DISK_IMG="$PROJECT_ROOT/iso/mikeos.img"
BENCHMARK_LOG="$PROJECT_ROOT/build/desktop_benchmark_results.log"
TMP_LOG="/tmp/mikeos_desktop_bench.log"

if [ ! -f "$KERNEL" ] || [ ! -f "$DISK_IMG" ]; then
    "$PROJECT_ROOT/scripts/build.sh"
fi

KVM_FLAGS=()
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_FLAGS=("-enable-kvm" "-cpu" "host")
else
    KVM_FLAGS=("-cpu" "max")
fi

echo "=========================================================="
echo "          EJECUTANDO MIKE DESKTOP BENCHMARK (QEMU)"
echo "=========================================================="

mkdir -p "$PROJECT_ROOT/build"
qemu-system-x86_64 \
    "${KVM_FLAGS[@]}" \
    -kernel "$KERNEL" \
    -drive file="$DISK_IMG",format=raw,if=virtio \
    -initrd "$INITRAMFS" \
    -append "root=/dev/vda rw console=tty0 console=ttyS0 quiet panic=1 mikeos_desktop_bench=1" \
    -vga std -nographic \
    -m 512M \
    -no-reboot > "$TMP_LOG" 2>&1 || true

awk '/MIKE DESKTOP BENCHMARK/{flag=1} /reboot: Restarting system/{flag=0} flag' "$TMP_LOG" | tee "$BENCHMARK_LOG"

echo ""
echo "Resultados detallados guardados en: $BENCHMARK_LOG"
