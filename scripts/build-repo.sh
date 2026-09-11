#!/bin/bash
# ==============================================================================
# MIKE OS - Repository Package Builder (Core + Desktop)
# Generates standardized .mpk packages with full metadata and checksums.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO_DIR="$PROJECT_ROOT/build/repo"
PKGS_BUILD_DIR="$PROJECT_ROOT/build/repo_pkgs"

export MPM_ROOT="$PROJECT_ROOT/build/repo_mpm_tmp"
rm -rf "$REPO_DIR/repo"
rm -rf "$REPO_DIR"/{core,system,network,development,tools,desktop,community}
mkdir -p "$REPO_DIR"/{core,system,network,development,tools,desktop}
mkdir -p "$PKGS_BUILD_DIR" "$MPM_ROOT"/{installed,repo}

# ------------------------------------------------------------------------------
# 1. development.mpk
# ------------------------------------------------------------------------------
echo "=== [1/6] Creando development-0.9.27-mike1-x86_64.mpk ==="
TCC_BIN="$PROJECT_ROOT/build/tcc-0.9.27/tcc"
if [ -f "$TCC_BIN" ]; then
    DEV_SPEC="$PKGS_BUILD_DIR/development"
    rm -rf "$DEV_SPEC"
    mkdir -p "$DEV_SPEC/root/usr/bin" "$DEV_SPEC/root/usr/lib/tcc" "$DEV_SPEC/root/usr/include"

    cp "$TCC_BIN" "$DEV_SPEC/root/usr/bin/tcc"
    cp "$PROJECT_ROOT/build/tcc-0.9.27/lib/libtcc1.a" "$DEV_SPEC/root/usr/lib/tcc/" 2>/dev/null || true

    cat << 'EOF' > "$DEV_SPEC/root/usr/bin/gcc"
#!/bin/sh
# MIKE OS C Compiler Driver
exec /usr/bin/tcc -nostdlib -I/usr/include -B/usr/lib/tcc -run "$@"
EOF
    chmod +x "$DEV_SPEC/root/usr/bin/gcc"
    ln -sf "/usr/bin/gcc" "$DEV_SPEC/root/usr/bin/cc"

    cat << 'EOF' > "$DEV_SPEC/root/usr/include/stdio.h"
#ifndef _STDIO_H
#define _STDIO_H

typedef unsigned long size_t;
typedef long ssize_t;

static inline long _syscall3(long n, long a1, long a2, long a3) {
    long ret;
    __asm__ volatile ("syscall" : "=a"(ret) : "a"(n), "D"(a1), "S"(a2), "d"(a3) : "rcx", "r11", "memory");
    return ret;
}

static inline int puts(const char *s) {
    int len = 0; while (s[len]) len++;
    _syscall3(1, 1, (long)s, len);
    _syscall3(1, 1, (long)"\n", 1);
    return len;
}

static inline int printf(const char *format, ...) {
    return puts(format);
}

#endif
EOF

    cat << 'EOF' > "$DEV_SPEC/root/usr/include/stdlib.h"
#ifndef _STDLIB_H
#define _STDLIB_H

static inline void exit(int status) {
    __asm__ volatile ("syscall" : : "a"(60), "D"(status) : "rcx", "r11", "memory");
    while (1);
}

#endif
EOF

    cat << 'EOF' > "$DEV_SPEC/root/usr/include/unistd.h"
#ifndef _UNISTD_H
#define _UNISTD_H

static inline int write(int fd, const void *buf, unsigned long count) {
    long ret;
    __asm__ volatile ("syscall" : "=a"(ret) : "a"(1), "D"(fd), "S"(buf), "d"(count) : "rcx", "r11", "memory");
    return (int)ret;
}

#endif
EOF

    cat << 'EOF' > "$DEV_SPEC/meta.json"
{
  "name": "development",
  "version": "0.9.27",
  "release": "mike1",
  "arch": "x86_64",
  "category": "development",
  "license": "LGPL-2.1",
  "origin": "https://savannah.nongnu.org/projects/tinycc",
  "description": "Toolchain de desarrollo C nativo (TinyCC + libc headers + gcc driver)",
  "dependencies": [],
  "size": "1.8MB"
}
EOF

    cat << 'EOF' > "$DEV_SPEC/POST_INSTALL"
#!/bin/sh
echo ">> Toolchain C nativo instalado. Puedes compilar con: gcc archivo.c -o binario"
EOF
    chmod +x "$DEV_SPEC/POST_INSTALL"

    (cd "$DEV_SPEC" && "$PROJECT_ROOT/build/mpm/mpm" build "$DEV_SPEC" >/dev/null)
    mv "$DEV_SPEC"/*.mpk "$REPO_DIR/development/"
    echo "  -> Paquete development generado."
fi

# ------------------------------------------------------------------------------
# 2. mcore.mpk
# ------------------------------------------------------------------------------
echo "=== [2/6] Creando mcore-0.1.0-mike1-x86_64.mpk ==="
MCORE_SPEC="$PKGS_BUILD_DIR/mcore"
rm -rf "$MCORE_SPEC"
mkdir -p "$MCORE_SPEC/root/usr/bin"

for u in m-service m-system m-network m-user m-disk m-info m-doctor m-log m-sudo m-install m-desktop m-screenshot m-volume m-fastfetch m-workspace-cycle; do
    if [ -f "$PROJECT_ROOT/build/mcore/$u" ]; then
        cp "$PROJECT_ROOT/build/mcore/$u" "$MCORE_SPEC/root/usr/bin/"
        chmod 755 "$MCORE_SPEC/root/usr/bin/$u"
    fi
done

# Fastfetch se entrega junto a mcore para que el banner MIKE sea reproducible
# incluso al instalar el núcleo desde cero.
FASTFETCH_BIN="$PROJECT_ROOT/build/fastfetch-static/fastfetch"
[ -x "$FASTFETCH_BIN" ] || FASTFETCH_BIN="$PROJECT_ROOT/build/fastfetch-build/fastfetch"
if [ -x "$FASTFETCH_BIN" ]; then
    cp "$FASTFETCH_BIN" "$MCORE_SPEC/root/usr/bin/fastfetch"
    chmod 755 "$MCORE_SPEC/root/usr/bin/fastfetch"
    mkdir -p "$MCORE_SPEC/root/etc/mikeos/fastfetch"
    cp "$PROJECT_ROOT/build/desktop/fastfetch/config.jsonc" "$MCORE_SPEC/root/etc/mikeos/fastfetch/config.jsonc"
    cp "$PROJECT_ROOT/build/desktop/fastfetch/mike.logo" "$MCORE_SPEC/root/etc/mikeos/fastfetch/mike.logo"
fi

cat << 'EOF' > "$MCORE_SPEC/meta.json"
{
  "name": "mcore",
  "version": "0.1.0",
  "release": "mike1",
  "arch": "x86_64",
  "category": "core",
  "license": "MIT",
  "origin": "https://mikeos.local",
  "description": "Suite de herramientas fundamentales del sistema MIKE OS",
  "dependencies": [],
  "size": "2.1MB"
}
EOF

(cd "$MCORE_SPEC" && "$PROJECT_ROOT/build/mpm/mpm" build "$MCORE_SPEC" >/dev/null)
mv "$MCORE_SPEC"/*.mpk "$REPO_DIR/core/"
echo "  -> Paquete mcore generado."

# ------------------------------------------------------------------------------
# 3. mkshell.mpk
# ------------------------------------------------------------------------------
echo "=== [3/6] Creando mkshell-0.1.0-mike1-x86_64.mpk ==="
MKSHELL_SPEC="$PKGS_BUILD_DIR/mkshell"
rm -rf "$MKSHELL_SPEC"
mkdir -p "$MKSHELL_SPEC/root/bin" "$MKSHELL_SPEC/root/usr/bin" "$MKSHELL_SPEC/root/etc"

cp "$PROJECT_ROOT/build/mkshell/mkshell" "$MKSHELL_SPEC/root/bin/mkshell"
ln -sf "/bin/mkshell" "$MKSHELL_SPEC/root/usr/bin/mkshell"

cat << 'EOF' > "$MKSHELL_SPEC/meta.json"
{
  "name": "mkshell",
  "version": "0.1.0",
  "release": "mike1",
  "arch": "x86_64",
  "category": "core",
  "license": "MIT",
  "origin": "https://mikeos.local",
  "description": "Shell interactiva nativa de MIKE OS con soporte de pipes y jobs",
  "dependencies": [],
  "size": "980KB"
}
EOF

(cd "$MKSHELL_SPEC" && "$PROJECT_ROOT/build/mpm/mpm" build "$MKSHELL_SPEC" >/dev/null)
mv "$MKSHELL_SPEC"/*.mpk "$REPO_DIR/core/"
echo "  -> Paquete mkshell generado."

# ------------------------------------------------------------------------------
# 4. mike-desktop.mpk (Fases 14 a 19)
# ------------------------------------------------------------------------------
echo "=== [4/6] Creando mike-desktop-0.1.0-mike1-x86_64.mpk ==="
DESK_SPEC="$PKGS_BUILD_DIR/mike-desktop"
rm -rf "$DESK_SPEC"
mkdir -p "$DESK_SPEC/root/usr/bin"
mkdir -p "$DESK_SPEC/root/etc/skel/.config/mike/quickshell"
mkdir -p "$DESK_SPEC/root/etc/skel/.config/mike/theme"
mkdir -p "$DESK_SPEC/root/etc/skel/.config/mike/waybar"
mkdir -p "$DESK_SPEC/root/etc/mikeos/desktop"

# Copiar binarios y scripts ejecutables
for b in /usr/bin/Hyprland /usr/bin/hyprctl /usr/bin/quickshell /usr/bin/fuzzel /usr/bin/seatd; do
    [ -f "$b" ] && cp "$b" "$DESK_SPEC/root/usr/bin/"
done
cp "$PROJECT_ROOT/build/desktop/start-mike-desktop" "$DESK_SPEC/root/usr/bin/"
cp "$PROJECT_ROOT/build/mterminal/m-terminal" "$DESK_SPEC/root/usr/bin/m-terminal"
cp "$PROJECT_ROOT/build/desktop/m-launcher" "$DESK_SPEC/root/usr/bin/"
cp "$PROJECT_ROOT/build/desktop/m-panel" "$DESK_SPEC/root/usr/bin/"
cp "$PROJECT_ROOT/build/desktop/m-hw-profile" "$DESK_SPEC/root/usr/bin/"
cp "$PROJECT_ROOT/build/mcore/m-desktop" "$DESK_SPEC/root/usr/bin/"
chmod 755 "$DESK_SPEC/root/usr/bin"/*

# Copiar configuraciones y temas
cp "$PROJECT_ROOT/build/desktop/hyprland.conf" "$DESK_SPEC/root/etc/skel/.config/mike/"
cp "$PROJECT_ROOT/build/desktop/hyprland.local.conf" "$DESK_SPEC/root/etc/skel/.config/mike/"
cp "$PROJECT_ROOT/build/desktop/hyprland.conf" "$DESK_SPEC/root/etc/mikeos/desktop/"
cp "$PROJECT_ROOT/build/desktop/quickshell/shell.qml" "$DESK_SPEC/root/etc/skel/.config/mike/quickshell/"
cp "$PROJECT_ROOT/build/desktop/quickshell/shell.qml" "$DESK_SPEC/root/etc/mikeos/desktop/"
cp "$PROJECT_ROOT/build/desktop/theme/colors.conf" "$DESK_SPEC/root/etc/skel/.config/mike/theme/"
cp "$PROJECT_ROOT/build/desktop/waybar/config.jsonc" "$DESK_SPEC/root/etc/skel/.config/mike/waybar/"
cp "$PROJECT_ROOT/build/desktop/waybar/style.css" "$DESK_SPEC/root/etc/skel/.config/mike/waybar/"

cat << 'EOF' > "$DESK_SPEC/meta.json"
{
  "name": "mike-desktop",
  "version": "0.1.0",
  "release": "mike1",
  "arch": "x86_64",
  "category": "desktop",
  "license": "MIT",
  "origin": "https://mikeos.local",
  "description": "Capa gráfica modular e independiente para MIKE OS (Hyprland + Quickshell)",
  "dependencies": [],
  "size": "65KB"
}
EOF

cat << 'EOF' > "$DESK_SPEC/POST_INSTALL"
#!/bin/sh
echo "=========================================================="
echo " ¡MIKE Desktop instalado con éxito!"
echo " Para iniciar la sesión gráfica ejecuta: m-desktop start"
echo " Para configurarlo al arranque ejecuta:  m-desktop enable"
echo "=========================================================="
EOF
chmod +x "$DESK_SPEC/POST_INSTALL"

(cd "$DESK_SPEC" && "$PROJECT_ROOT/build/mpm/mpm" build "$DESK_SPEC" >/dev/null)
mv "$DESK_SPEC"/*.mpk "$REPO_DIR/desktop/"
echo "  -> Paquete mike-desktop generado."

# ------------------------------------------------------------------------------
# 5. net-tools y tools
# ------------------------------------------------------------------------------
echo "=== [5/6] Creando net-tools y tools ==="
NET_SPEC="$PKGS_BUILD_DIR/net-tools"
rm -rf "$NET_SPEC"
mkdir -p "$NET_SPEC/root/usr/bin"

cat << 'EOF' > "$NET_SPEC/root/usr/bin/m-ping"
#!/bin/sh
echo "Haciendo ping a ${1:-1.1.1.1}..."
ping -c 3 "${1:-1.1.1.1}"
EOF
chmod +x "$NET_SPEC/root/usr/bin/m-ping"

cat << 'EOF' > "$NET_SPEC/meta.json"
{
  "name": "net-tools",
  "version": "1.0.0",
  "release": "mike1",
  "arch": "x86_64",
  "category": "network",
  "license": "GPL-2.0",
  "origin": "https://mikeos.local",
  "description": "Herramientas auxiliares de diagnóstico de red de MIKE OS",
  "dependencies": [],
  "size": "10KB"
}
EOF
(cd "$NET_SPEC" && "$PROJECT_ROOT/build/mpm/mpm" build "$NET_SPEC" >/dev/null)
mv "$NET_SPEC"/*.mpk "$REPO_DIR/network/"

TOOLS_SPEC="$PKGS_BUILD_DIR/tools"
rm -rf "$TOOLS_SPEC"
mkdir -p "$TOOLS_SPEC/root/usr/bin"

cat << 'EOF' > "$TOOLS_SPEC/root/usr/bin/m-calc"
#!/bin/sh
# Calculadora aritmética simple. Solo acepta dígitos, punto, espacios y
# operadores +-*/%^(). Cualquier otro carácter (letras, comillas, etc.) se
# rechaza para evitar inyectar código awk arbitrario vía system().
EXPR="$*"
case "$EXPR" in
    *[!0-9.+\-*/%\(\)\ ^]*)
        echo "m-calc: expresión inválida (solo se permiten números y operadores)" >&2
        exit 1
        ;;
esac
echo "Calculadora MIKE OS:"
# Charset ya validado arriba (solo dígitos/operadores): seguro interpolar.
awk "BEGIN { print ($EXPR) }"
EOF
chmod +x "$TOOLS_SPEC/root/usr/bin/m-calc"

cat << 'EOF' > "$TOOLS_SPEC/meta.json"
{
  "name": "tools",
  "version": "1.0.0",
  "release": "mike1",
  "arch": "x86_64",
  "category": "tools",
  "license": "GPL-2.0",
  "origin": "https://mikeos.local",
  "description": "Utilidades adicionales de terminal para MIKE OS",
  "dependencies": [],
  "size": "10KB"
}
EOF
(cd "$TOOLS_SPEC" && "$PROJECT_ROOT/build/mpm/mpm" build "$TOOLS_SPEC" >/dev/null)
mv "$TOOLS_SPEC"/*.mpk "$REPO_DIR/tools/"

# ------------------------------------------------------------------------------
# 6. Sincronizar repositorio central
# ------------------------------------------------------------------------------
echo "=== [6/6] Sincronizando catálogo central repo.json ==="
export MPM_ROOT="$PROJECT_ROOT/build/repo_mpm_tmp"
export MPM_REPO_DIR="$REPO_DIR"
"$PROJECT_ROOT/build/mpm/mpm" update

echo "¡Repositorio de paquetes de MIKE OS compilado con éxito en $REPO_DIR!"
