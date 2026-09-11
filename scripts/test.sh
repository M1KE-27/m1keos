#!/bin/bash
# ==============================================================================
# MIKE OS - Automated Comprehensive Test Suite (Fase 7)
# Validates 15 core subsystems in QEMU and reports exact PASS/FAIL status.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KERNEL="$PROJECT_ROOT/kernel/arch/x86/boot/bzImage"
INITRAMFS="$PROJECT_ROOT/iso/initramfs.cpio.gz"
DISK_IMG="$PROJECT_ROOT/iso/mikeos.img"
TEST_LOG="$PROJECT_ROOT/build/test_suite_results.log"
TMP_LOG="/tmp/mikeos_test_run.log"

if [ ! -f "$KERNEL" ] || [ ! -f "$DISK_IMG" ] || [ ! -f "$INITRAMFS" ]; then
    echo "Construyendo sistema completo antes de ejecutar los tests..."
    "$PROJECT_ROOT/scripts/build.sh"
fi

KVM_FLAGS=()
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_FLAGS=("-enable-kvm" "-cpu" "host")
else
    KVM_FLAGS=("-cpu" "max")
fi

echo "=========================================================="
echo "          EJECUTANDO MIKE OS TEST SUITE (15 FASES)"
echo "=========================================================="

mkdir -p "$PROJECT_ROOT/build"
set +e
qemu-system-x86_64 \
    "${KVM_FLAGS[@]}" \
    -kernel "$KERNEL" \
    -drive file="$DISK_IMG",format=raw,if=virtio \
    -initrd "$INITRAMFS" \
    -append "root=/dev/vda rw console=ttyS0 quiet panic=1 mikeos_test_suite=1" \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    -device virtio-vga \
    -display none \
    -serial stdio \
    -m 1024M \
    -no-reboot > "$TMP_LOG" 2>&1
QEMU_STATUS=$?
set -e

# Filtrar y mostrar el reporte de tests
sed -n '/MIKE OS TEST SUITE/,/TOTAL:/p' "$TMP_LOG" | tee "$TEST_LOG"

echo ""
echo "Resultados detallados guardados en: $TEST_LOG"

if ! tr -d '\r' < "$TMP_LOG" | grep -q '^TOTAL: 21/21 PASS$'; then
    echo "ERROR: la suite no completó 21/21 pruebas. Revisa $TMP_LOG." >&2
    exit 1
fi
if [ "$QEMU_STATUS" -ne 0 ]; then
    echo "Aviso: QEMU terminó con código $QEMU_STATUS después de completar todas las pruebas." >&2
fi
echo "=== TODAS LAS PRUEBAS COMPLETADAS: 21/21 PASS ==="
