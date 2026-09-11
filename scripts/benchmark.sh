#!/bin/bash
# ==============================================================================
# MIKE OS - Automated Separated Benchmark Runner (Core vs Desktop)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KERNEL="$PROJECT_ROOT/kernel/arch/x86/boot/bzImage"
INITRAMFS="$PROJECT_ROOT/iso/initramfs.cpio.gz"
DISK_IMG="$PROJECT_ROOT/iso/mikeos.img"
BENCHMARK_LOG="$PROJECT_ROOT/build/benchmark_results.log"
TMP_LOG_CORE="/tmp/mikeos_bench_core.log"
TMP_LOG_DESK="/tmp/mikeos_bench_desk.log"

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
echo "          EJECUTANDO BENCHMARKS SEPARADOS DE MIKE OS"
echo "=========================================================="

echo ">>> [1/2] Midiendo Rendimiento de MIKE OS CORE (Headless TTY)..."
qemu-system-x86_64 \
    "${KVM_FLAGS[@]}" \
    -kernel "$KERNEL" \
    -drive file="$DISK_IMG",format=raw,if=virtio \
    -initrd "$INITRAMFS" \
    -append "root=/dev/vda rw console=ttyS0 quiet panic=1 mikeos_benchmark=1" \
    -vga none -nographic \
    -m 512M \
    -no-reboot > "$TMP_LOG_CORE" 2>&1 || true

echo ">>> [2/2] Midiendo Rendimiento de MIKE DESKTOP (VGA/FrameBuffer inicializado)..."
qemu-system-x86_64 \
    "${KVM_FLAGS[@]}" \
    -kernel "$KERNEL" \
    -drive file="$DISK_IMG",format=raw,if=virtio \
    -initrd "$INITRAMFS" \
    -append "root=/dev/vda rw console=tty0 console=ttyS0 quiet panic=1 mikeos_benchmark=1" \
    -vga std -nographic \
    -m 512M \
    -no-reboot > "$TMP_LOG_DESK" 2>&1 || true

{
    echo "=========================================================="
    echo "         MIKE OS — INFORME DE BENCHMARKS SEPARADOS"
    echo "=========================================================="
    echo ""
    echo "1. MIKE OS CORE (Sin entorno gráfico / Headless TTY)"
    sed -n '/=== \[MIKE OS BENCHMARK \/ TELEMETRÍA\] ===/,/========================================/p' "$TMP_LOG_CORE"
    echo ""
    echo "2. MIKE DESKTOP (Con subsistema de pantalla gráfica VGA/DRM inicializado)"
    sed -n '/=== \[MIKE OS BENCHMARK \/ TELEMETRÍA\] ===/,/========================================/p' "$TMP_LOG_DESK"
} | tee "$BENCHMARK_LOG"

echo ""
echo "Resultados consolidados guardados en: $BENCHMARK_LOG"
