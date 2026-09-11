#!/bin/bash
# ==============================================================================
# MIKE OS - Complete System Build Script (Core Consolidation)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS_DIR="$PROJECT_ROOT/rootfs"
ISO_DIR="$PROJECT_ROOT/iso"
KERNEL_IMAGE="$PROJECT_ROOT/kernel/arch/x86/boot/bzImage"

# Kernel Linux propio del proyecto (rama de desarrollo de torvalds/linux,
# fijado por commit exacto para reproducibilidad -- no es un tag estable,
# así que sin este pin "git clone" traería un árbol distinto cada vez).
KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
KERNEL_COMMIT="388b607d107c07aaade04c7f22f344cab6bdccd3"
KERNEL_CONFIG_FRAGMENT="$PROJECT_ROOT/.config"

BUSYBOX_VERSION="1.36.1"
RUNIT_VERSION="2.1.2"
DROPBEAR_VERSION="2024.86"
TCC_VERSION="0.9.27"
BASH_VERSION_="5.2.37"
CURL_VERSION_="8.21.0"

# SHA256 fijados sobre la descarga verificada en este entorno de build. Si un
# mirror sirve un tarball distinto (compromiso, corrupción), el build aborta
# en vez de compilar código no verificado.
BUSYBOX_SHA256="b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314"
RUNIT_SHA256="6fd0160cb0cf1207de4e66754b6d39750cff14bb0aa66ab49490992c0c47ba18"
DROPBEAR_SHA256="e78936dffc395f2e0db099321d6be659190966b99712b55c530dd0a1822e0a5e"
TCC_SHA256="de23af78fca90ce32dff2dd45b3432b2334740bb9bb7b05bf60fdbfc396ceb9c"
BASH_SHA256="9599b22ecd1d5787ad7d3b7bf0c59f312b3396d1e281175dd1f8a4014da621ff"
CURL_SHA256="0ebe99e278b9083db5730d557d7fbd354167aa3182b4724df75631f9bc15ba48"
JQ_VERSION_="1.8.2"
JQ_SHA256="b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f"

verify_sha256() {
    _file="$1"
    _expected="$2"
    _actual="$(sha256sum "$_file" | cut -d' ' -f1)"
    if [ "$_actual" != "$_expected" ]; then
        echo "ERROR: SHA256 no coincide para $_file" >&2
        echo "  esperado: $_expected" >&2
        echo "  obtenido: $_actual" >&2
        rm -f "$_file"
        exit 1
    fi
}

# Árbol de archivos estáticos del rootfs: /etc, los servicios runit, el init de
# la fase 1... Antes vivían como heredocs dentro de este script (836 líneas de
# contenido incrustado); ahora son archivos reales bajo build/etc-tree/, que se
# pueden leer, editar con resaltado de sintaxis y probar por separado.
ETC_TREE="$PROJECT_ROOT/build/etc-tree"

install_etc() {
    # $1 = ruta relativa dentro del rootfs; $2 = modo octal (por defecto 644).
    _rel="$1"
    _mode="${2:-644}"
    _src="$ETC_TREE/$_rel"
    if [ ! -f "$_src" ]; then
        echo "ERROR: falta $_src (build/etc-tree incompleto)" >&2
        exit 1
    fi
    mkdir -p "$ROOTFS_DIR/$(dirname "$_rel")"
    cp "$_src" "$ROOTFS_DIR/$_rel"
    chmod "$_mode" "$ROOTFS_DIR/$_rel"
}

echo "=== [1/8] Preparando entorno de construcción de MIKE OS ==="
mkdir -p "$BUILD_DIR" "$ROOTFS_DIR" "$ISO_DIR" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/docs" "$PROJECT_ROOT/tests"

if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "=== [1b/8] Clonando y compilando el kernel Linux ($KERNEL_COMMIT) ==="
    if [ ! -d "$PROJECT_ROOT/kernel/.git" ]; then
        git clone "$KERNEL_REPO" "$PROJECT_ROOT/kernel"
    fi
    # kbuild se niega a compilar desde una ruta con espacios ("source
    # directory cannot contain spaces or colons", Makefile del kernel), y la
    # carpeta del proyecto vive dentro de "Proyectos 2026". Cuando toca, se
    # monta el árbol del kernel en una ruta sin espacios y se compila desde
    # ahí: los archivos son los mismos, sólo cambia el nombre del camino.
    KERNEL_SRC="$PROJECT_ROOT/kernel"
    KERNEL_BIND=""
    case "$KERNEL_SRC" in
        *[[:space:]]*|*:*)
            KERNEL_BIND="/mnt/mikeos-kernel"
            echo "Ruta con espacios: montando el kernel en $KERNEL_BIND para compilarlo."
            sudo mkdir -p "$KERNEL_BIND"
            mountpoint -q "$KERNEL_BIND" || sudo mount --bind "$KERNEL_SRC" "$KERNEL_BIND"
            KERNEL_SRC="$KERNEL_BIND"
            ;;
    esac
    cd "$KERNEL_SRC"
    git checkout -q "$KERNEL_COMMIT"
    make defconfig
    ./scripts/kconfig/merge_config.sh -m .config "$KERNEL_CONFIG_FRAGMENT"
    make olddefconfig
    make -j"$(nproc)" bzImage
    cd "$PROJECT_ROOT"
    [ -n "$KERNEL_BIND" ] && sudo umount "$KERNEL_BIND" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. Compilar BusyBox (estático)
# ------------------------------------------------------------------------------
echo "=== [2/8] Compilando BusyBox ($BUSYBOX_VERSION) ==="
cd "$BUILD_DIR"
if [ ! -d "busybox-$BUSYBOX_VERSION" ]; then
    if [ ! -f "busybox-$BUSYBOX_VERSION.tar.bz2" ]; then
        curl -fsSL "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2" -o "busybox-$BUSYBOX_VERSION.tar.bz2"
    fi
    verify_sha256 "busybox-$BUSYBOX_VERSION.tar.bz2" "$BUSYBOX_SHA256"
    tar -xjf "busybox-$BUSYBOX_VERSION.tar.bz2"
fi

cd "$BUILD_DIR/busybox-$BUSYBOX_VERSION"
# srctree=. objtree=.: el Makefile de BusyBox define srctree como $(CURDIR),
# una ruta absoluta, y luego la usa sin comillas en "include $(srctree)/...".
# Con un directorio de proyecto que lleva un espacio ("Proyectos 2026") make
# parte la ruta en dos y aborta con "No rule to make target". Forzarlo a "."
# vale porque siempre construimos dentro del propio árbol de BusyBox.
BB_MAKE=(make srctree=. objtree=.)
if [ ! -f "busybox" ]; then
    "${BB_MAKE[@]}" defconfig
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config
    sed -i 's/CONFIG_FEATURE_TC_INGRESS=y/CONFIG_FEATURE_TC_INGRESS=n/' .config
    "${BB_MAKE[@]}" -j"$(nproc)"
fi

# ------------------------------------------------------------------------------
# 3. Compilar runit (estático)
# ------------------------------------------------------------------------------
echo "=== [3/8] Compilando runit ($RUNIT_VERSION) ==="
cd "$BUILD_DIR"
if [ ! -d "admin/runit-$RUNIT_VERSION" ]; then
    if [ ! -f "runit-$RUNIT_VERSION.tar.gz" ]; then
        curl -fsSL "https://smarden.org/runit/runit-$RUNIT_VERSION.tar.gz" -o "runit-$RUNIT_VERSION.tar.gz"
    fi
    verify_sha256 "runit-$RUNIT_VERSION.tar.gz" "$RUNIT_SHA256"
    tar -xzf "runit-$RUNIT_VERSION.tar.gz"
fi

cd "$BUILD_DIR/admin/runit-$RUNIT_VERSION"
if [ ! -f "command/runit" ]; then
    echo "gcc -O2 -static -std=gnu89" > src/conf-cc
    echo "gcc -static" > src/conf-ld
    rm -rf compile command
    package/compile
fi

# ------------------------------------------------------------------------------
# 4. Compilar Dropbear SSH (estático)
# ------------------------------------------------------------------------------
echo "=== [4/8] Compilando Dropbear SSH ($DROPBEAR_VERSION) ==="
cd "$BUILD_DIR"
if [ ! -d "dropbear-$DROPBEAR_VERSION" ]; then
    if [ ! -f "dropbear-$DROPBEAR_VERSION.tar.bz2" ]; then
        curl -fsSL "https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR_VERSION.tar.bz2" -o "dropbear-$DROPBEAR_VERSION.tar.bz2"
    fi
    verify_sha256 "dropbear-$DROPBEAR_VERSION.tar.bz2" "$DROPBEAR_SHA256"
    tar -xjf "dropbear-$DROPBEAR_VERSION.tar.bz2"
fi

cd "$BUILD_DIR/dropbear-$DROPBEAR_VERSION"
if [ ! -f "dropbear" ]; then
    echo "#define DROPBEAR_SVR_PASSWORD_AUTH 0" > localoptions.h
    ./configure --enable-static --disable-zlib --disable-syslog CC="gcc" CFLAGS="-O2 -static" LDFLAGS="-static" >/dev/null
    make -j"$(nproc)" PROGRAMS="dropbear dropbearkey dbclient scp" STATIC=1 >/dev/null
fi

# ------------------------------------------------------------------------------
# 5. Compilar MKShell y Toolchain
# ------------------------------------------------------------------------------
echo "=== [5/8] Compilando MKShell y Toolchain ==="
mkdir -p "$BUILD_DIR/mkshell"
gcc -O2 -static -Wall "$BUILD_DIR/mkshell/mkshell.c" -o "$BUILD_DIR/mkshell/mkshell"

# m-sudo: binario setuid-root real (no wrapper de shell sobre "su", que
# exige contraseña -- inservible con las cuentas bloqueadas por diseño).
gcc -O2 -static -Wall "$PROJECT_ROOT/build/mcore/m-sudo-src.c" -o "$BUILD_DIR/mcore/m-sudo"

# Resolutor de dependencias de MPM: calcula el árbol completo de cualquiera
# de los ~15.200 paquetes de core+extra de Arch contra el catálogo local, sin
# una petición de red por dependencia. Es una pieza interna -- se instala en
# /usr/lib/mpm y no en /usr/bin -- porque la única orden que el usuario
# ejecuta es "mpm". Ver cabecera de resolver.c.
mkdir -p "$BUILD_DIR/mpm/bin"
gcc -O2 -static -Wall "$PROJECT_ROOT/build/mpm/resolver.c" -o "$BUILD_DIR/mpm/bin/resolver"

# MTerminal: emulador Wayland/GTK+VTE propio de MIKE OS. No depende de Kitty
# ni de otro terminal externo; VTE se ocupa de PTY, scrollback y secuencias
# ANSI, mientras que MKShell proporciona el prompt y el autocompletado.
mkdir -p "$BUILD_DIR/mterminal"
gcc -O2 -Wall $(pkg-config --cflags gtk+-3.0 vte-2.91) \
    "$PROJECT_ROOT/build/mterminal/mterminal.c" \
    -o "$BUILD_DIR/mterminal/m-terminal" \
    $(pkg-config --libs gtk+-3.0 vte-2.91)

# M-Settings: panel de ajustes nativo (barra, workspaces, blur, opacidad,
# animación, color de acento, teclado). Escribe ~/.config/mike/settings.conf
# y delega la aplicación en caliente a m-apply-settings.
mkdir -p "$BUILD_DIR/settings"
gcc -O2 -Wall $(pkg-config --cflags gtk+-3.0) \
    "$PROJECT_ROOT/build/desktop/settings/m-settings.c" \
    -o "$BUILD_DIR/settings/m-settings" \
    $(pkg-config --libs gtk+-3.0)

# M-Wallpapers: navegador nativo de Wallhaven (API pública, SFW/general
# fijo). Delega HTTP+JSON en m-wallhaven (curl+jq); esta app solo pinta.
gcc -O2 -Wall $(pkg-config --cflags gtk+-3.0) \
    "$PROJECT_ROOT/build/desktop/settings/m-wallpapers.c" \
    -o "$BUILD_DIR/settings/m-wallpapers" \
    $(pkg-config --libs gtk+-3.0)

# M-Welcome: panel de bienvenida de primer arranque (controles básicos).
# Sale al instante si ~/.config/mike/.welcomed ya existe.
gcc -O2 -Wall $(pkg-config --cflags gtk+-3.0) \
    "$PROJECT_ROOT/build/desktop/settings/m-welcome.c" \
    -o "$BUILD_DIR/settings/m-welcome" \
    $(pkg-config --libs gtk+-3.0)

# TinyCC
cd "$BUILD_DIR"
if [ ! -d "tcc-$TCC_VERSION" ]; then
    if [ ! -f "tcc-$TCC_VERSION.tar.bz2" ]; then
        curl -fsSL "https://download.savannah.gnu.org/releases/tinycc/tcc-$TCC_VERSION.tar.bz2" -o "tcc-$TCC_VERSION.tar.bz2"
    fi
    verify_sha256 "tcc-$TCC_VERSION.tar.bz2" "$TCC_SHA256"
    tar -xjf "tcc-$TCC_VERSION.tar.bz2"
fi
cd "$BUILD_DIR/tcc-$TCC_VERSION"
if [ ! -f "tcc" ]; then
    ./configure --prefix=/usr --enable-static --extra-cflags="-static -O2" --extra-ldflags="-static" >/dev/null
    make tcc -j"$(nproc)" >/dev/null || true
fi
cd "$BUILD_DIR/tcc-$TCC_VERSION/lib"
if [ ! -f "libtcc1.a" ]; then
    ../tcc -c libtcc1.c 2>/dev/null || true
    ../tcc -c alloca86_64.S 2>/dev/null || true
    ../tcc -c va_list.c 2>/dev/null || true
    ar rcs libtcc1.a libtcc1.o alloca86_64.o va_list.o 2>/dev/null || true
fi

# Bash (estático): shell de login real -- MKShell sigue disponible, pero
# bash es el intérprete por defecto que se espera de un sistema Unix normal.
cd "$BUILD_DIR"
if [ ! -d "bash-$BASH_VERSION_" ]; then
    if [ ! -f "bash-$BASH_VERSION_.tar.gz" ]; then
        curl -fsSL "https://ftp.gnu.org/gnu/bash/bash-$BASH_VERSION_.tar.gz" -o "bash-$BASH_VERSION_.tar.gz"
    fi
    verify_sha256 "bash-$BASH_VERSION_.tar.gz" "$BASH_SHA256"
    tar -xzf "bash-$BASH_VERSION_.tar.gz"
fi
cd "$BUILD_DIR/bash-$BASH_VERSION_"
if [ ! -f "bash" ]; then
    # GCC 14+ trata implicit-function-declaration como error por defecto;
    # el código de bash 5.2 (K&R-style en varios ficheros bundled) necesita
    # que se rebaje a warning para compilar tal cual viene upstream.
    ./configure --enable-static-link --without-bash-malloc \
        CC="gcc" \
        CFLAGS="-O2 -static -std=gnu17 -Wno-error=implicit-function-declaration -Wno-error=int-conversion" \
        LDFLAGS="-static" >/dev/null
    make -j"$(nproc)" >/dev/null
fi

# curl (estático precompilado): base de la barra de progreso "bonita"
# (curl -#) que usa mpm en cada descarga. Horneado en la imagen base -- no
# como receta -- para que la barra salga siempre, no solo tras instalarlo.
cd "$BUILD_DIR"
if [ ! -f "curl-linux-x86_64-glibc-$CURL_VERSION_.tar.xz" ]; then
    curl -fsSL "https://github.com/stunnel/static-curl/releases/download/$CURL_VERSION_/curl-linux-x86_64-glibc-$CURL_VERSION_.tar.xz" \
        -o "curl-linux-x86_64-glibc-$CURL_VERSION_.tar.xz"
fi
verify_sha256 "curl-linux-x86_64-glibc-$CURL_VERSION_.tar.xz" "$CURL_SHA256"
mkdir -p "curl-$CURL_VERSION_"
tar -xJf "curl-linux-x86_64-glibc-$CURL_VERSION_.tar.xz" -C "curl-$CURL_VERSION_"

# jq: binario oficial precompilado. Horneado en base -- m-wallhaven lo
# necesita como dependencia dura para parsear la respuesta JSON de la API.
if [ ! -f "jq-linux-amd64-$JQ_VERSION_" ]; then
    curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION_/jq-linux-amd64" \
        -o "jq-linux-amd64-$JQ_VERSION_"
fi
verify_sha256 "jq-linux-amd64-$JQ_VERSION_" "$JQ_SHA256"
chmod +x "jq-linux-amd64-$JQ_VERSION_"

# Construir paquetes MPM
chmod +x "$PROJECT_ROOT/scripts/build-repo.sh" "$BUILD_DIR/mpm/mpm"
"$PROJECT_ROOT/scripts/build-repo.sh"

# ------------------------------------------------------------------------------
# 6. Construir el Root Filesystem
# ------------------------------------------------------------------------------
echo "=== [6/8] Ensamblando RootFS de MIKE OS ==="
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"/{bin,sbin,dev,proc,sys,run,tmp,root,home/mike,var,boot}
mkdir -p "$ROOTFS_DIR"/usr/{bin,sbin,lib,include,share/udhcpc}
mkdir -p "$ROOTFS_DIR"/var/{log,service,lib/mpm/installed,lib/mpm/repo,lib/mpm/backups,lib/mpm/recipes}
mkdir -p "$ROOTFS_DIR"/etc/{mikeos,runit,dropbear,skel}
mkdir -p "$ROOTFS_DIR"/etc/sv/{console,syslog,network,dropbear}

chmod 1777 "$ROOTFS_DIR/tmp"

# Nodos estáticos de dispositivos esenciales
mknod -m 600 "$ROOTFS_DIR/dev/console" c 5 1 2>/dev/null || true
mknod -m 666 "$ROOTFS_DIR/dev/tty" c 5 0 2>/dev/null || true
mknod -m 666 "$ROOTFS_DIR/dev/tty0" c 4 0 2>/dev/null || true
mknod -m 666 "$ROOTFS_DIR/dev/tty1" c 4 1 2>/dev/null || true
mknod -m 666 "$ROOTFS_DIR/dev/tty2" c 4 2 2>/dev/null || true
mknod -m 666 "$ROOTFS_DIR/dev/null" c 1 3 2>/dev/null || true
mknod -m 666 "$ROOTFS_DIR/dev/zero" c 1 5 2>/dev/null || true
mknod -m 666 "$ROOTFS_DIR/dev/ptmx" c 5 2 2>/dev/null || true

# Instalar BusyBox
cd "$BUILD_DIR/busybox-$BUSYBOX_VERSION"
# "make install" de BusyBox pasa CONFIG_PREFIX sin comillas a applets/install.sh
# (ver Makefile.custom), así que tampoco admite espacios en el destino. Se
# instala en un directorio temporal sin espacios y de ahí se copia al rootfs
# conservando los enlaces simbólicos de los applets.
BB_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/mikeos-busybox-XXXXXX")"
"${BB_MAKE[@]}" CONFIG_PREFIX="$BB_STAGE" install >/dev/null
cp -a "$BB_STAGE"/. "$ROOTFS_DIR"/
rm -rf "$BB_STAGE"

# m-sudo depende de "su" (symlink al multi-call busybox). Sin setuid, busybox
# rechaza su con "must be suid to work properly" y m-sudo queda inservible
# para "mike". Solo se otorga privilegio al applet "su" (busybox.conf), no a
# todo el binario, para no abrir de más el resto de applets.
# OJO: el bit setuid NO se pone aquí -- el strip global de ELF que corre más
# adelante reescribe el binario y el kernel limpia S_ISUID en cada escritura.
# Se aplica al final, dentro de la sesión fakeroot de empaquetado (ver
# create-disk.sh y el paso de initramfs), justo antes de leerlo por última vez.
install_etc etc/busybox.conf 644

# Instalar runit
cp "$BUILD_DIR/admin/runit-$RUNIT_VERSION/command"/* "$ROOTFS_DIR/sbin/"
for cmd in runit runit-init runsv runsvchdir runsvdir sv svlogd chpst utmpset; do
    ln -sf "/sbin/$cmd" "$ROOTFS_DIR/usr/bin/$cmd" 2>/dev/null || true
    ln -sf "/sbin/$cmd" "$ROOTFS_DIR/bin/$cmd" 2>/dev/null || true
done

# Instalar Dropbear
cp "$BUILD_DIR/dropbear-$DROPBEAR_VERSION"/{dropbear,dropbearkey,dbclient,scp} "$ROOTFS_DIR/usr/bin/"
ln -sf "/usr/bin/dbclient" "$ROOTFS_DIR/usr/bin/ssh" 2>/dev/null || true

# Instalar MKShell
cp "$BUILD_DIR/mkshell/mkshell" "$ROOTFS_DIR/bin/mkshell"
ln -sf "/bin/mkshell" "$ROOTFS_DIR/usr/bin/mkshell" 2>/dev/null || true

# Instalar bash (shell por defecto)
cp "$BUILD_DIR/bash-$BASH_VERSION_/bash" "$ROOTFS_DIR/bin/bash"
strip --strip-unneeded "$ROOTFS_DIR/bin/bash" 2>/dev/null || true
ln -sf "/bin/bash" "$ROOTFS_DIR/usr/bin/bash" 2>/dev/null || true

# Instalar curl (base de la barra de progreso de mpm)
cp "$BUILD_DIR/curl-$CURL_VERSION_/curl" "$ROOTFS_DIR/usr/bin/curl"
chmod 755 "$ROOTFS_DIR/usr/bin/curl"

# Instalar jq (parseo JSON: m-wallhaven y cualquier script que lo necesite)
cp "$BUILD_DIR/jq-linux-amd64-$JQ_VERSION_" "$ROOTFS_DIR/usr/bin/jq"
chmod 755 "$ROOTFS_DIR/usr/bin/jq"

# Fastfetch compilado desde la fuente oficial, con un logo MIKE y una
# configuración reducida para conservar el perfil base ultraligero.
FASTFETCH_BIN="$BUILD_DIR/fastfetch-static/fastfetch"
[ -x "$FASTFETCH_BIN" ] || FASTFETCH_BIN="$BUILD_DIR/fastfetch-build/fastfetch"
if [ -x "$FASTFETCH_BIN" ]; then
    cp "$FASTFETCH_BIN" "$ROOTFS_DIR/usr/bin/fastfetch"
    chmod 755 "$ROOTFS_DIR/usr/bin/fastfetch"
else
    echo "Aviso: Fastfetch no fue compilado; m-info conservará su fallback." >&2
fi

# Instalar MCore
for util in m-service m-system m-network m-user m-disk m-info m-doctor m-log m-sudo m-install m-screenshot m-volume m-metrics m-audio-setup m-fastfetch m-workspace-cycle m-drivers m-wifi m-bluetooth m-wallhaven; do
    cp "$BUILD_DIR/mcore/$util" "$ROOTFS_DIR/usr/bin/"
    chmod 755 "$ROOTFS_DIR/usr/bin/$util"
done
# Base de identificadores PCI: sin ella m-drivers enseña "10de:2583" en vez
# de "NVIDIA GeForce RTX 3050", que es justo lo que se le pide.
if [ -f /usr/share/hwdata/pci.ids ]; then
    mkdir -p "$ROOTFS_DIR/usr/share/hwdata"
    cp /usr/share/hwdata/pci.ids "$ROOTFS_DIR/usr/share/hwdata/pci.ids"
fi

# Piezas internas de MPM. Fuera de /usr/bin a propósito: el usuario escribe
# "mpm" y nada más; que el resolutor o el sincronizador fueran órdenes
# sueltas era justo la separación entre componentes que sobraba.
mkdir -p "$ROOTFS_DIR/usr/lib/mpm"
cp "$BUILD_DIR/mpm/bin/resolver" "$ROOTFS_DIR/usr/lib/mpm/resolver"
cp "$PROJECT_ROOT/build/mpm/sync"  "$ROOTFS_DIR/usr/lib/mpm/sync"
chmod 755 "$ROOTFS_DIR/usr/lib/mpm/resolver" "$ROOTFS_DIR/usr/lib/mpm/sync"

# Catálogo de core/extra horneado en la imagen. Sin esto, la primera
# instalación de cualquier paquete tendría que descargar 9 MB de catálogo
# antes de empezar. Se refresca solo cuando pasa de una semana.
echo "Generando catálogo de paquetes de Arch..."
mkdir -p "$ROOTFS_DIR/var/lib/mpm/sync" "$ROOTFS_DIR/var/lib/mpm/installed" "$ROOTFS_DIR/var/lib/mpm/tmp"
if MPM_SYNC_DIR="$ROOTFS_DIR/var/lib/mpm/sync" "$PROJECT_ROOT/build/mpm/sync"; then
    :
else
    echo "Aviso: no se pudo generar el catálogo; se descargará en el primer uso." >&2
fi

# "sudo" es la convención universal de Unix; que un usuario tenga que saber
# que aquí se llama "m-sudo" es fricción innecesaria.
ln -sf m-sudo "$ROOTFS_DIR/usr/bin/sudo"

# Recetas MPM de ejemplo: solo texto (recipe.conf), no el software en sí.
# "mpm build-recipe" descarga+empaqueta bajo demanda dentro del sistema ya
# instalado -- la imagen base no crece.
mkdir -p "$ROOTFS_DIR/usr/share/mikeos/recipes"
cp -a "$PROJECT_ROOT/build/recipes/." "$ROOTFS_DIR/usr/share/mikeos/recipes/"

# Instalar MPM
cp "$BUILD_DIR/mpm/mpm" "$ROOTFS_DIR/usr/bin/mpm"
chmod 755 "$ROOTFS_DIR/usr/bin/mpm"

# Desplegar binarios y librerías de MIKE Desktop (Hyprland, Quickshell,
# MTerminal, Fuzzel, Mesa, GBM, LLVM)
# ROOTFS_DIR se exporta explícitamente para que el build sea reproducible cuando
# el proyecto se mueve a otra máquina o se compila desde un directorio distinto.
export MIKEOS_ROOTFS_DIR="$ROOTFS_DIR"
export MIKEOS_DESKTOP_DIR="$BUILD_DIR/desktop"
export MIKEOS_BUILD_DIR="$BUILD_DIR"
python3 - << 'PYEOF'
import subprocess, os, shutil, glob

rootfs = os.environ['MIKEOS_ROOTFS_DIR']
desktop_dir = os.environ['MIKEOS_DESKTOP_DIR']
build_dir = os.environ['MIKEOS_BUILD_DIR']
# wpctl, pactl, amixer, grim, slurp y wl-copy se copiaban más abajo con un cp
# suelto que NO pasa por este resolutor, así que llegaban al sistema sin sus
# bibliotecas: wpctl moría con "libwireplumber-0.5.so.0: cannot open shared
# object file" y el volumen no se podía leer.
bins = ['/usr/bin/Hyprland', '/usr/bin/Xwayland', '/usr/bin/start-hyprland', '/usr/bin/hyprctl', '/usr/bin/quickshell', '/usr/bin/fuzzel', '/usr/bin/seatd', '/usr/bin/seatd-launch', '/usr/bin/swaybg', '/usr/bin/bwrap', '/usr/bin/wpctl', '/usr/bin/pactl', '/usr/bin/amixer', '/usr/bin/grim', '/usr/bin/slurp', '/usr/bin/wl-copy', '/usr/bin/pipewire', '/usr/bin/pipewire-pulse', '/usr/bin/wireplumber', '/usr/bin/dbus-daemon', '/usr/bin/dbus-launch', '/usr/bin/dbus-run-session', '/usr/bin/zstd', '/usr/bin/unzstd', '/usr/bin/iwctl', '/usr/bin/bluetoothctl', f'{build_dir}/mterminal/m-terminal', f'{build_dir}/settings/m-settings', f'{build_dir}/settings/m-wallpapers', f'{build_dir}/settings/m-welcome']
lib_links = {}

os.makedirs(f"{rootfs}/usr/bin", exist_ok=True)
os.makedirs(f"{rootfs}/usr/lib", exist_ok=True)
os.makedirs(f"{rootfs}/lib64", exist_ok=True)

for b in bins:
    if os.path.exists(b):
        shutil.copy2(b, f"{rootfs}/usr/bin/")

queue = list(bins)
for dri_f in glob.glob('/usr/lib/dri/*.so'):
    queue.append(dri_f)
for gbm_f in glob.glob('/usr/lib/gbm/*.so'):
    queue.append(gbm_f)
for gl_f in glob.glob('/usr/lib/libgallium*.so*') + glob.glob('/usr/lib/libLLVM*.so*') + glob.glob('/usr/lib/libEGL*.so*') + glob.glob('/usr/lib/libGL*.so*') + glob.glob('/usr/lib/libgbm*.so*'):
    queue.append(gl_f)
for p in glob.glob('/usr/lib/qt6/plugins/platforms/libqwayland*.so') + glob.glob('/usr/lib/qt6/plugins/wayland-*.so') + glob.glob('/usr/lib/qt6/plugins/wayland-*/*.so') + glob.glob('/usr/lib/qt6/plugins/platforminputcontexts/*.so') + glob.glob('/usr/lib/qt6/qml/Quickshell/**/*.so', recursive=True) + glob.glob('/usr/lib/qt6/qml/QtQuick/**/*.so', recursive=True) + glob.glob('/usr/lib/qt6/qml/QtCore/**/*.so', recursive=True) + glob.glob('/usr/lib/qt6/qml/QtQml/**/*.so', recursive=True) + glob.glob('/usr/lib/qt6/qml/QtWaylandClient/**/*.so', recursive=True):
    queue.append(p)
for p in ('/usr/lib/iwd/iwd', '/usr/lib/bluetooth/bluetoothd', f'{rootfs}/usr/bin/curl', f'{rootfs}/usr/bin/jq'):
    if os.path.exists(p):
        queue.append(p)
for p in glob.glob('/usr/lib/glycin-loaders/**/*', recursive=True):
    if os.path.isfile(p):
        queue.append(p)

# Librerías propietarias/host-específicas que nunca deben viajar al guest:
# MIKE OS corre siempre sobre virtio-gpu (virgl) dentro de QEMU, jamás sobre
# hardware NVIDIA real, así que el driver propietario del host es puro peso
# muerto (y confundiría a GLVND si además existiese el JSON de vendor).
def is_excluded(path):
    base = os.path.basename(path).lower()
    # OJO: nunca usar substrings sueltos como "cuda" -- "libicudata.so"
    # contiene "cuda" (i-CUDA-ta) y por eso se coló como falso positivo,
    # rompiendo Hyprland (dependía de libicudata vía libicuuc). Por eso el
    # filtro exige el prefijo completo del nombre de librería.
    return 'nvidia' in base or base.startswith('libcuda.so') or base.startswith('libcudart.so')

visited = set()
while queue:
    item = queue.pop(0)
    if item in visited:
        continue
    visited.add(item)
    if is_excluded(item):
        continue
    if os.path.exists(item):
        real_item = os.path.realpath(item)
        # Los ejecutables ya se copiaron a /usr/bin; solo recorremos su ldd.
        # No duplicarlos accidentalmente en /usr/lib (MTerminal incluido).
        if not item.startswith('/usr/bin/') and not item.endswith('/usr/bin/curl') and not item.endswith('/usr/bin/jq') and not item.endswith('/mterminal/m-terminal') and not item.endswith('/settings/m-settings') and not item.endswith('/settings/m-wallpapers') and not item.endswith('/settings/m-welcome') and not item.endswith('/iwd/iwd') and not item.endswith('/bluetooth/bluetoothd') and '/glycin-loaders/' not in item:
            lib_links[item] = real_item
        try:
            out = subprocess.check_output(['ldd', item]).decode('utf-8')
            for line in out.splitlines():
                if '=>' in line:
                    parts = line.split('=>')
                    req = parts[0].strip()
                    target = parts[1].strip().split(' ')[0]
                    if target and os.path.isabs(target) and os.path.exists(target) and not is_excluded(target):
                        real_target = os.path.realpath(target)
                        lib_links[target] = real_target
                        lib_links[f"/usr/lib/{req}"] = real_target
                        if real_target not in visited:
                            queue.append(real_target)
                elif line.strip().startswith('/'):
                    target = line.strip().split(' ')[0]
                    if target and os.path.exists(target) and not is_excluded(target):
                        real_target = os.path.realpath(target)
                        lib_links[target] = real_target
                        if real_target not in visited:
                            queue.append(real_target)
        except Exception:
            pass

copied_real = set()
for req, real in lib_links.items():
    if real not in copied_real and os.path.isfile(real):
        copied_real.add(real)
        real_base = os.path.basename(real)
        dest_f = f"{rootfs}/usr/lib/{real_base}"
        if os.path.islink(dest_f) or os.path.exists(dest_f):
            os.remove(dest_f)
        shutil.copy2(real, dest_f)

for req, real in lib_links.items():
    req_base = os.path.basename(req)
    real_base = os.path.basename(real)
    if req_base != real_base:
        link_path = f"{rootfs}/usr/lib/{req_base}"
        if os.path.islink(link_path) or os.path.exists(link_path):
            os.remove(link_path)
        try:
            os.symlink(real_base, link_path)
        except Exception:
            pass

real_ld = os.path.realpath('/lib64/ld-linux-x86-64.so.2')
for p in [f"{rootfs}/lib64/ld-linux-x86-64.so.2", f"{rootfs}/usr/lib/ld-linux-x86-64.so.2", f"{rootfs}/usr/lib64/ld-linux-x86-64.so.2", f"{rootfs}/lib/ld-linux-x86-64.so.2"]:
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if os.path.islink(p) or os.path.exists(p):
        os.remove(p)
    shutil.copy2(real_ld, p)

if os.path.exists('/usr/lib/dri'):
    os.makedirs(f"{rootfs}/usr/lib/dri", exist_ok=True)
    for dri_file in os.listdir('/usr/lib/dri'):
        if is_excluded(dri_file):
            continue
        src = f"/usr/lib/dri/{dri_file}"
        if os.path.isfile(src) or os.path.islink(src):
            if os.path.islink(src):
                target = os.readlink(src)
                try:
                    os.symlink(target, f"{rootfs}/usr/lib/dri/{dri_file}")
                except FileExistsError:
                    pass
            else:
                shutil.copy2(src, f"{rootfs}/usr/lib/dri/")

if os.path.exists('/usr/lib/gbm'):
    os.makedirs(f"{rootfs}/usr/lib/gbm", exist_ok=True)
    for gbm_file in os.listdir('/usr/lib/gbm'):
        if is_excluded(gbm_file):
            continue
        src = f"/usr/lib/gbm/{gbm_file}"
        if os.path.isfile(src) or os.path.islink(src):
            if os.path.islink(src):
                target = os.readlink(src)
                try:
                    os.symlink(target, f"{rootfs}/usr/lib/gbm/{gbm_file}")
                except FileExistsError:
                    pass
            else:
                shutil.copy2(src, f"{rootfs}/usr/lib/gbm/")

import glob
for extra_pattern in ['/usr/lib/libgallium*', '/usr/lib/libEGL*', '/usr/lib/libGL*', '/usr/lib/libGLES*', '/usr/lib/libgbm*']:
    for f in glob.glob(extra_pattern):
        if is_excluded(f):
            continue
        if os.path.islink(f):
            target = os.readlink(f)
            try:
                os.symlink(target, f"{rootfs}/usr/lib/{os.path.basename(f)}")
            except FileExistsError:
                pass
        elif os.path.isfile(f):
            shutil.copy2(f, f"{rootfs}/usr/lib/")

if os.path.exists('/usr/share/X11/xkb'):
    os.makedirs(f"{rootfs}/usr/share/X11", exist_ok=True)
    shutil.copytree(os.path.realpath('/usr/share/X11/xkb'), f"{rootfs}/usr/share/X11/xkb", dirs_exist_ok=True)

if os.path.exists('/usr/share/glvnd'):
    os.makedirs(f"{rootfs}/usr/share", exist_ok=True)
    shutil.copytree('/usr/share/glvnd', f"{rootfs}/usr/share/glvnd", dirs_exist_ok=True)
    # Sin GPU NVIDIA real dentro de la VM: si GLVND encuentra un vendor JSON
    # de NVIDIA intentará esa ICD primero y fallará antes de caer a Mesa.
    for vendor_json in glob.glob(f"{rootfs}/usr/share/glvnd/egl_vendor.d/*nvidia*") + \
                        glob.glob(f"{rootfs}/usr/share/glvnd/**/*nvidia*", recursive=True):
        try:
            os.remove(vendor_json)
        except Exception:
            pass

if os.path.exists('/usr/share/drirc.d'):
    os.makedirs(f"{rootfs}/usr/share", exist_ok=True)
    shutil.copytree('/usr/share/drirc.d', f"{rootfs}/usr/share/drirc.d", dirs_exist_ok=True)

if os.path.exists('/etc/fonts'):
    os.makedirs(f"{rootfs}/etc", exist_ok=True)
    shutil.copytree('/etc/fonts', f"{rootfs}/etc/fonts", dirs_exist_ok=True)

if os.path.exists('/usr/share/fonts/liberation'):
    os.makedirs(f"{rootfs}/usr/share/fonts/liberation", exist_ok=True)
    shutil.copytree('/usr/share/fonts/liberation', f"{rootfs}/usr/share/fonts/liberation", dirs_exist_ok=True)

# Sin esto, cualquier app GTK (Firefox incluido) cae a glifos "tofu" para
# emoji/iconos y a una fuente sans genérica en vez de la Cantarell que GNOME
# y la mayoría de temas esperan. Deliberadamente NO se incluye Noto CJK
# (300MB+) ni DejaVu completo (480MB) -- duplicarían el tamaño de la imagen
# para cobertura que la mayoría no necesita; están disponibles como receta
# mpm bajo demanda si hace falta japonés/chino/coreano.
for extra_font_dir in ('Adwaita', 'cantarell', 'twemoji'):
    src_font = f'/usr/share/fonts/{extra_font_dir}'
    if os.path.exists(src_font):
        shutil.copytree(src_font, f"{rootfs}/usr/share/fonts/{extra_font_dir}", dirs_exist_ok=True)

# Selective QML copy (only Quickshell, QtQuick, QtCore, QtQml, QtWaylandClient)
for qml_mod in ['Quickshell', 'QtQuick', 'QtCore', 'QtQml', 'QtWaylandClient', 'Qt']:
    src_mod = f'/usr/lib/qt6/qml/{qml_mod}'
    if os.path.exists(src_mod):
        os.makedirs(f"{rootfs}/usr/lib/qt6/qml/{qml_mod}", exist_ok=True)
        shutil.copytree(src_mod, f"{rootfs}/usr/lib/qt6/qml/{qml_mod}", dirs_exist_ok=True)

# Selective Qt6 plugins copy
for plug_dir in ['platforms', 'wayland-shell-integration', 'wayland-graphics-integration-client', 'platforminputcontexts']:
    src_plug = f'/usr/lib/qt6/plugins/{plug_dir}'
    if os.path.exists(src_plug):
        os.makedirs(f"{rootfs}/usr/lib/qt6/plugins/{plug_dir}", exist_ok=True)
        shutil.copytree(src_plug, f"{rootfs}/usr/lib/qt6/plugins/{plug_dir}", dirs_exist_ok=True)

for glycin_dir in ('/usr/lib/glycin-loaders', '/usr/share/glycin-loaders'):
    if os.path.exists(glycin_dir):
        # swaybg (y otras apps GTK4 modernas) delegan la decodificación de
        # imágenes a los procesos sandboxeados de glycin en vez de gdk-pixbuf
        # directo. Sin estos binarios y sus .conf de registro: "No image
        # loaders are configured" aunque libpng/libjpeg estén presentes.
        shutil.copytree(glycin_dir, f"{rootfs}{glycin_dir}", dirs_exist_ok=True, symlinks=True)

if os.path.exists('/usr/lib/iwd/iwd'):
    os.makedirs(f"{rootfs}/usr/lib/iwd", exist_ok=True)
    shutil.copy2('/usr/lib/iwd/iwd', f"{rootfs}/usr/lib/iwd/iwd")
    os.chmod(f"{rootfs}/usr/lib/iwd/iwd", 0o755)

if os.path.exists('/usr/lib/bluetooth/bluetoothd'):
    os.makedirs(f"{rootfs}/usr/lib/bluetooth", exist_ok=True)
    shutil.copy2('/usr/lib/bluetooth/bluetoothd', f"{rootfs}/usr/lib/bluetooth/bluetoothd")
    os.chmod(f"{rootfs}/usr/lib/bluetooth/bluetoothd", 0o755)

# Políticas D-Bus: sin ellas iwd/bluetoothd no pueden registrar su nombre en
# el bus del sistema y iwctl/bluetoothctl no consiguen hablar con ellos.
# Configuración del bus de SESIÓN. dbus-run-session la exige por ruta fija y
# sin ella la sesión gráfica no arranca: "Failed to open session.conf". El bus
# de sesión es lo que permite a WirePlumber reservar la tarjeta de sonido y a
# MPRIS informar de lo que se reproduce.
if os.path.exists('/usr/share/dbus-1/session.conf'):
    os.makedirs(f"{rootfs}/usr/share/dbus-1", exist_ok=True)
    shutil.copy2('/usr/share/dbus-1/session.conf', f"{rootfs}/usr/share/dbus-1/session.conf")
if os.path.isdir('/usr/share/dbus-1/session.d'):
    shutil.copytree('/usr/share/dbus-1/session.d', f"{rootfs}/usr/share/dbus-1/session.d", dirs_exist_ok=True)

for dbus_conf in ('bluetooth.conf', 'iwd-dbus.conf'):
    src = f'/usr/share/dbus-1/system.d/{dbus_conf}'
    if os.path.exists(src):
        os.makedirs(f"{rootfs}/usr/share/dbus-1/system.d", exist_ok=True)
        shutil.copy2(src, f"{rootfs}/usr/share/dbus-1/system.d/{dbus_conf}")

# Stubs de compatibilidad que el glibc moderno del host fusionó dentro de
# libc.so.6 (libdl/libpthread/librt/libutil/libnsl). Nada del sistema base
# los necesita como dependencia directa, así que el volcado por ldd nunca
# los copia -- pero paquetes de terceros instalados luego vía mpm (ej.
# binarios oficiales de Node.js) sí los referencian explícitamente.
for compat_lib in ('libdl.so.2', 'libpthread.so.0', 'librt.so.1', 'libutil.so.1', 'libnsl.so.1', 'libasound.so.2'):
    src_compat = f'/usr/lib/{compat_lib}'
    if os.path.exists(src_compat) and not os.path.exists(f"{rootfs}/usr/lib/{compat_lib}"):
        shutil.copy2(src_compat, f"{rootfs}/usr/lib/{compat_lib}")

if os.path.exists('/etc/ssl/certs/ca-certificates.crt'):
    # Sin esto, curl real (instalado vía receta) no puede verificar HTTPS:
    # "error adding trust anchors from file". busybox wget no lo necesita
    # (no verifica certs), por eso el fallo solo aparece tras instalar curl.
    os.makedirs(f"{rootfs}/etc/ssl/certs", exist_ok=True)
    shutil.copy(os.path.realpath('/etc/ssl/certs/ca-certificates.crt'), f"{rootfs}/etc/ssl/certs/ca-certificates.crt")

if os.path.exists('/usr/share/mime/mime.cache'):
    # GIO's g_content_type_guess() (usado por gdk-pixbuf/GTK para reconocer
    # formatos de imagen) depende de la base shared-mime-info. Sin ella,
    # CUALQUIER imagen -- PNG incluido -- falla con "Couldn't recognize the
    # image file format" pese a tener libpng/gdk-pixbuf presentes.
    shutil.copytree('/usr/share/mime', f"{rootfs}/usr/share/mime", dirs_exist_ok=True)

if os.path.exists('/usr/share/libinput'):
    shutil.copytree('/usr/share/libinput', f"{rootfs}/usr/share/libinput", dirs_exist_ok=True)

# PipeWire y WirePlumber: sin servidor de audio no hay volumen real que leer
# ni ajustar, sólo un control decorativo. Son 3,6 MB y traen sonido de verdad.
# Los módulos (.so de SPA, plugins de PipeWire) y sus configuraciones no los
# ve el resolutor de dependencias, porque se cargan a mano en tiempo de
# ejecución: hay que copiarlos enteros.
# /usr/share/alsa es obligatorio: libasound lo lee por ruta fija para saber
# abrir un dispositivo. Sin él, el plugin ALSA de PipeWire carga pero no
# consigue abrir la tarjeta, y WirePlumber no expone ningún destino de audio
# aunque el kernel sí vea la tarjeta.
for _d in ('/usr/lib/spa-0.2', '/usr/lib/pipewire-0.3', '/usr/lib/wireplumber-0.5',
           '/usr/share/pipewire', '/usr/share/wireplumber', '/usr/share/alsa',
           '/usr/share/alsa-card-profile'):
    if os.path.exists(_d):
        shutil.copytree(_d, f"{rootfs}{_d}", dirs_exist_ok=True, symlinks=True)

if os.path.exists('/usr/lib/gdk-pixbuf-2.0'):
    # Sin este directorio (loaders.cache + loaders/), gdk-pixbuf no reconoce
    # NINGÚN formato de imagen (ni siquiera PNG compilado-in): swaybg y
    # cualquier app GTK que cargue imágenes falla con "Couldn't recognize
    # the image file format" pese a tener libpng/libjpeg presentes.
    shutil.copytree('/usr/lib/gdk-pixbuf-2.0', f"{rootfs}/usr/lib/gdk-pixbuf-2.0", dirs_exist_ok=True)

if os.path.exists('/usr/share/terminfo'):
    os.makedirs(f"{rootfs}/usr/share", exist_ok=True)
    shutil.copytree('/usr/share/terminfo', f"{rootfs}/usr/share/terminfo", dirs_exist_ok=True)
    # El host trae ~2900 entradas de terminfo (ncurses completo), casi
    # todas de hardware de los 80 que nadie va a usar para conectarse a
    # MIKE OS. Nos quedamos solo con los emuladores reales con los que
    # alguien podría hacer SSH o abrir MTerminal (que usa xterm-256color).
    _TERMINFO_KEEP = {
        'linux', 'xterm', 'xterm-color', 'xterm-16color', 'xterm-88color',
        'xterm-256color', 'xterm-kitty', 'xterm-ghostty', 'alacritty',
        'foot', 'foot-extra', 'screen', 'screen-256color', 'screen-256color-bce',
        'tmux', 'tmux-256color', 'rxvt', 'rxvt-unicode', 'rxvt-unicode-256color',
        'vt100', 'vt102', 'vt220', 'ansi', 'dumb', 'konsole', 'konsole-256color',
        'gnome', 'gnome-256color', 'putty', 'putty-256color', 'st', 'st-256color',
    }
    for term in glob.glob(f"{rootfs}/usr/share/terminfo/*/*"):
        if os.path.basename(term) not in _TERMINFO_KEEP:
            try:
                os.remove(term)
            except OSError:
                pass

# No copiamos el runtime Python del host al perfil base: ningún binario
# preinstalado lo necesita y arrastraba ~93 MiB de módulos/SDK. Python queda
# como paquete opcional para recetas y aplicaciones que lo requieran.

wallpaper = os.path.join(desktop_dir, 'wallpaper.png')
if os.path.exists(wallpaper):
    os.makedirs(f"{rootfs}/usr/share/backgrounds", exist_ok=True)
    os.makedirs(f"{rootfs}/etc/skel/.config/mike", exist_ok=True)
    shutil.copy2(wallpaper, f"{rootfs}/usr/share/backgrounds/wallpaper.png")
    shutil.copy2(wallpaper, f"{rootfs}/etc/skel/.config/mike/wallpaper.png")

# Optimizar tamaño: strip de símbolos ELF
print("Optimizando tamaño: eliminando símbolos de depuración ELF...")
for r_root, r_dirs, r_files in os.walk(rootfs):
    for r_f in r_files:
        r_p = os.path.join(r_root, r_f)
        if not os.path.islink(r_p) and os.path.isfile(r_p):
            try:
                with open(r_p, 'rb') as fp:
                    if fp.read(4) == b'\x7fELF':
                        subprocess.run(['strip', '--strip-unneeded', r_p], capture_output=True)
            except Exception:
                pass
PYEOF

echo "Preparando compatibilidad libudev..."
# libudev-zero es opcional: un fallo de red no debe dejar el sistema sin
# imagen. Si ya copiamos libudev del host, se conserva como fallback.
LIBUDEV_ZERO_DIR="${TMPDIR:-/tmp}/mikeos-libudev-zero"
LIBUDEV_ZERO_COMMIT="7a6eee2db11f2eb0f7fd065ae9597fcd270e6734"
if [ ! -d "$LIBUDEV_ZERO_DIR" ]; then
    ( git clone https://github.com/illiliti/libudev-zero.git "$LIBUDEV_ZERO_DIR" >/dev/null 2>&1 && \
      cd "$LIBUDEV_ZERO_DIR" && git checkout -q "$LIBUDEV_ZERO_COMMIT" ) || true
fi
if [ -d "$LIBUDEV_ZERO_DIR" ] && (cd "$LIBUDEV_ZERO_DIR" && make clean >/dev/null 2>&1 && make >/dev/null 2>&1); then
    rm -f "$ROOTFS_DIR/usr/lib/libudev.so"*
    cp "$LIBUDEV_ZERO_DIR/libudev.so.1" "$ROOTFS_DIR/usr/lib/"
    ln -sf libudev.so.1 "$ROOTFS_DIR/usr/lib/libudev.so"
else
    echo "Aviso: libudev-zero no disponible; se conserva la biblioteca del host."
fi

# Copiar paquetes al repositorio de MPM en rootfs sin duplicar el catálogo.
# La versión anterior copiaba también build/repo/repo/, duplicando el paquete
# gráfico (~80 MiB) y haciendo que el índice quedara en una ruta inesperada.
for category in core system network development tools desktop community; do
    if [ -d "$BUILD_DIR/repo/$category" ]; then
        mkdir -p "$ROOTFS_DIR/var/lib/mpm/repo/$category"
        cp -a "$BUILD_DIR/repo/$category"/. "$ROOTFS_DIR/var/lib/mpm/repo/$category/"
    fi
done
if [ -f "$BUILD_DIR/repo/repo.json" ]; then
    cp -a "$BUILD_DIR/repo/repo.json" "$ROOTFS_DIR/var/lib/mpm/repo/repo.json"
fi

# Enlaces de compatibilidad de shell estándar. bash real ya se instaló
# antes como /bin/bash -- NO pisarlo aquí con un symlink a mkshell.
ln -sf busybox "$ROOTFS_DIR/bin/sh"
ln -sf ../../bin/busybox "$ROOTFS_DIR/usr/bin/sh"
ln -sf ../../bin/mkshell "$ROOTFS_DIR/usr/bin/mkshell"
ln -sf ../usr/bin/env "$ROOTFS_DIR/bin/env"

echo "=== [7/8] Configurando /etc/mikeos, servicios runit y usuarios ==="

# /etc/mikeos/system.conf
install_etc etc/mikeos/system.conf 644

# Base de zonas horarias para que el instalador pueda aplicar la ubicación
# elegida sin depender de systemd ni de un paquete adicional.
if [ -d /usr/share/zoneinfo ]; then
    cp -a /usr/share/zoneinfo "$ROOTFS_DIR/usr/share/"
fi

install_etc etc/mkshell.rc 644

# /etc/profile: prompt limpio para bash (shell de login por defecto) +
# fastfetch al abrir terminal. Solo en shells interactivas ($- contiene
# "i"): si no, cualquier script que use bash -l (cron, scp con receta...)
# heredaría el banner y el prompt con colores, rompiendo su parseo.
install_etc etc/profile 644

# /etc/mikeos/network.conf
install_etc etc/mikeos/network.conf 644

# /etc/mikeos/services.conf
install_etc etc/mikeos/services.conf 644

# /etc/mikeos/users.conf
install_etc etc/mikeos/users.conf 644

# /etc/mikeos/boot.conf
install_etc etc/mikeos/boot.conf 644

# Perfil declarativo de compatibilidad. Estos módulos son seguros de intentar
# cargar (los integrados o ausentes simplemente se ignoran) y cubren QEMU,
# KVM, VMware, VirtualBox, Hyper-V, Xen y hardware físico común.
install_etc etc/mikeos/compat.conf 644

# /etc/passwd & /etc/shadow & /etc/group
install_etc etc/passwd 644

install_etc etc/shadow 600

install_etc etc/group 644

# /etc/hostname & /etc/hosts & /etc/resolv.conf & /etc/fstab
echo "mikeos" > "$ROOTFS_DIR/etc/hostname"

install_etc etc/hosts 644

install_etc etc/resolv.conf 644

# Zona horaria: sin /etc/localtime el sistema muestra UTC crudo (reloj de
# Waybar/Quickshell desfasado respecto a la hora real del usuario). RTC de
# QEMU corre en UTC (default); este archivo es lo único que falta para que
# se muestre en hora local.
if [ -f /usr/share/zoneinfo/Europe/Madrid ]; then
    mkdir -p "$ROOTFS_DIR/usr/share/zoneinfo/Europe"
    cp /usr/share/zoneinfo/Europe/Madrid "$ROOTFS_DIR/usr/share/zoneinfo/Europe/Madrid"
    ln -sf /usr/share/zoneinfo/Europe/Madrid "$ROOTFS_DIR/etc/localtime"
    echo "Europe/Madrid" > "$ROOTFS_DIR/etc/timezone"
fi

# dropbear (y login) rechazan por defecto cualquier shell que no figure en
# /etc/shells con "invalid shell, rejected" — sin este archivo NADIE puede
# entrar por SSH usando /bin/mkshell como shell de login.
install_etc etc/shells 644

install_etc etc/fstab 644

install_etc etc/os-release 644

# Configurar skeleton /etc/skel y ~/.config/mike
mkdir -p "$ROOTFS_DIR/etc/skel/.config/mike/quickshell" "$ROOTFS_DIR/etc/skel/.config/mike/theme" "$ROOTFS_DIR/etc/skel/.config/mike/waybar"
mkdir -p "$ROOTFS_DIR/etc/mikeos/desktop"
mkdir -p "$ROOTFS_DIR/etc/mikeos/fastfetch"
cp "$BUILD_DIR/desktop/fastfetch/config.jsonc" "$ROOTFS_DIR/etc/mikeos/fastfetch/config.jsonc"
cp "$BUILD_DIR/desktop/fastfetch/mike.logo" "$ROOTFS_DIR/etc/mikeos/fastfetch/mike.logo"
cp "$BUILD_DIR/desktop/hyprland.conf" "$ROOTFS_DIR/etc/skel/.config/mike/"
cp "$BUILD_DIR/desktop/hyprland.local.conf" "$ROOTFS_DIR/etc/skel/.config/mike/"
cp "$BUILD_DIR/desktop/hyprland.conf" "$ROOTFS_DIR/etc/mikeos/desktop/"
cp "$BUILD_DIR/desktop/hyprland.local.conf" "$ROOTFS_DIR/etc/mikeos/desktop/"
chown root:wheel "$ROOTFS_DIR/etc/mikeos/desktop" "$ROOTFS_DIR/etc/mikeos/desktop/hyprland.local.conf" 2>/dev/null || true
chmod 775 "$ROOTFS_DIR/etc/mikeos/desktop" 2>/dev/null || true
chmod 664 "$ROOTFS_DIR/etc/mikeos/desktop/hyprland.local.conf" 2>/dev/null || true
# El QML del escritorio, shell.qml incluido. Ya no hay plantilla que rellenar:
# shell.qml lee ~/.config/mike/settings.json en marcha, así que es un archivo
# estático como cualquier otro componente. m-apply-settings los copia a la
# configuración del usuario para que QML los resuelva como import implícito
# de carpeta.
mkdir -p "$ROOTFS_DIR/etc/mikeos/desktop"
for _qc in "$BUILD_DIR"/desktop/quickshell/*.qml; do
    cp "$_qc" "$ROOTFS_DIR/etc/mikeos/desktop/$(basename "$_qc")"
done
# qmldir declara el singleton Paleta -- de donde salen los colores de todo el
# escritorio -- y, con él presente, también el resto de componentes: QML deja
# de descubrirlos solo. Se regenera para que añadir uno nuevo no rompa nada.
"$PROJECT_ROOT/scripts/qmldir.sh"
cp "$BUILD_DIR/desktop/quickshell/qmldir" "$ROOTFS_DIR/etc/mikeos/desktop/qmldir"
cp "$BUILD_DIR/desktop/theme/colors.conf" "$ROOTFS_DIR/etc/skel/.config/mike/theme/"
cp "$BUILD_DIR/desktop/waybar/config.jsonc" "$ROOTFS_DIR/etc/skel/.config/mike/waybar/"
cp "$BUILD_DIR/desktop/waybar/style.css" "$ROOTFS_DIR/etc/skel/.config/mike/waybar/"
cp "$BUILD_DIR/desktop/start-mike-desktop" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/desktop/m-panel" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/desktop/m-hw-profile" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/desktop/m-apply-settings" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/settings/m-settings" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/settings/m-wallpapers" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/settings/m-welcome" "$ROOTFS_DIR/usr/bin/"
chmod 755 "$ROOTFS_DIR/usr/bin/start-mike-desktop" "$ROOTFS_DIR/usr/bin/m-panel" "$ROOTFS_DIR/usr/bin/m-hw-profile" "$ROOTFS_DIR/usr/bin/m-apply-settings" "$ROOTFS_DIR/usr/bin/m-settings" "$ROOTFS_DIR/usr/bin/m-wallpapers" "$ROOTFS_DIR/usr/bin/m-welcome"

# Entradas .desktop: sin esto fuzzel (el selector de apps nativo, Super+Espacio)
# no tiene nada que listar.
mkdir -p "$ROOTFS_DIR/usr/share/applications"
cp "$BUILD_DIR/desktop/applications"/*.desktop "$ROOTFS_DIR/usr/share/applications/"

cp "$BUILD_DIR/desktop/m-launcher" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/mterminal/m-terminal" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/mcore/m-desktop" "$ROOTFS_DIR/usr/bin/"

# Copiar binarios del entorno gráfico y seat management
for b in /usr/bin/Hyprland /usr/bin/hyprctl /usr/bin/quickshell /usr/bin/fuzzel /usr/bin/seatd /usr/bin/seatd-launch /usr/bin/grim /usr/bin/slurp /usr/bin/wl-copy /usr/bin/wpctl /usr/bin/pactl /usr/bin/amixer; do
    [ -f "$b" ] && cp "$b" "$ROOTFS_DIR/usr/bin/"
done
chmod 755 "$ROOTFS_DIR/usr/bin"/* 2>/dev/null || true

# Carpetas estándar del usuario (especificación XDG user-dirs). Se crean en
# /etc/skel para que cualquier usuario nuevo las herede, y también en el home
# de mike, que ya existe. Screenshots va dentro de Pictures porque es donde
# m-screenshot guarda las capturas (ver OUT_DIR en build/mcore/m-screenshot).
MIKE_USER_DIRS="Desktop Downloads Documents Pictures Pictures/Screenshots Music Videos Projects"
for _base in "$ROOTFS_DIR/etc/skel" "$ROOTFS_DIR/home/mike" "$ROOTFS_DIR/root"; do
    for _d in $MIKE_USER_DIRS; do
        mkdir -p "$_base/$_d"
    done
done

# Las apps que siguen XDG (navegadores, gestores de archivos, diálogos GTK)
# leen estas rutas para saber dónde descargar o guardar. Sin el archivo, cada
# una improvisa y los archivos acaban repartidos por el home.
for _base in "$ROOTFS_DIR/etc/skel" "$ROOTFS_DIR/home/mike" "$ROOTFS_DIR/root"; do
    mkdir -p "$_base/.config"
    cat > "$_base/.config/user-dirs.dirs" <<'USERDIRS'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_MUSIC_DIR="$HOME/Music"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_PUBLICSHARE_DIR="$HOME/Desktop"
XDG_TEMPLATES_DIR="$HOME/Documents"
USERDIRS
done

mkdir -p "$ROOTFS_DIR/root/.config/mike"
cp -r "$ROOTFS_DIR/etc/skel/.config/mike"/* "$ROOTFS_DIR/root/.config/mike/" 2>/dev/null || true
mkdir -p "$ROOTFS_DIR/home/mike/.config/mike"
cp -r "$ROOTFS_DIR/etc/skel/.config/mike"/* "$ROOTFS_DIR/home/mike/.config/mike/" 2>/dev/null || true
chown -R 1000:1000 "$ROOTFS_DIR/home/mike" 2>/dev/null || true

# Script default de DHCP para udhcpc
mkdir -p "$ROOTFS_DIR/usr/share/udhcpc"
install_etc usr/share/udhcpc/default.script 755

# ------------------------------------------------------------------------------
# Servicios en /etc/sv
# ------------------------------------------------------------------------------
# /etc/sv/console/run
install_etc etc/sv/console/run 755

# /etc/sv/syslog/run
install_etc etc/sv/syslog/run 755

# /etc/sv/network/run
mkdir -p "$ROOTFS_DIR/etc/sv/network/log" "$ROOTFS_DIR/var/log/network"
install_etc etc/sv/network/run 755

install_etc etc/sv/network/log/run 755

# /etc/sv/dropbear/run
mkdir -p "$ROOTFS_DIR/etc/sv/dropbear/log" "$ROOTFS_DIR/var/log/dropbear"
install_etc etc/sv/dropbear/run 755

install_etc etc/sv/dropbear/log/run 755

# /etc/sv/seatd/run — seatd persistente como root, socket propiedad de mike.
# seatd-launch (invocado desde la sesión ya reducida a "mike" en
# start-mike-desktop) spawneaba su propio seatd sin privilegios, incapaz de
# abrir /dev/tty* para VT-switching. Un servicio runit dedicado corre seatd
# como root de verdad desde el arranque; start-mike-desktop solo se conecta.
mkdir -p "$ROOTFS_DIR/etc/sv/seatd/log" "$ROOTFS_DIR/var/log/seatd"
install_etc etc/sv/seatd/run 755

install_etc etc/sv/seatd/log/run 755

# /etc/dbus-1/system.conf: bus del sistema para iwd/bluetoothd. Simplificado
# frente al de Arch (que exige un usuario "dbus" separado y políticas
# granulares por servicio): aquí corre como root y con política por defecto
# permisiva -- coherente con el resto de MIKE OS, donde "root" ya es el
# límite de confianza único (mike escala vía m-sudo, no hay separación
# multiusuario real que defender).
mkdir -p "$ROOTFS_DIR/etc/dbus-1"
install_etc etc/dbus-1/system.conf 644

# /etc/sv/dbus-system/run — bus D-Bus del sistema. iwd y bluetoothd lo
# necesitan para registrar su nombre de servicio; sin él arrancan pero
# iwctl/bluetoothctl no consiguen conectar a nada.
mkdir -p "$ROOTFS_DIR/etc/sv/dbus-system/log" "$ROOTFS_DIR/var/log/dbus-system"
install_etc etc/sv/dbus-system/run 755
install_etc etc/sv/dbus-system/log/run 755

# /etc/sv/iwd/run — WiFi real (escaneo/conexión) en hardware físico. En
# QEMU (virtio-net) no encuentra ningún adaptador inalámbrico y se queda
# inactivo sin fallar; iwctl seguirá respondiendo pero listará 0 redes.
mkdir -p "$ROOTFS_DIR/etc/sv/iwd/log" "$ROOTFS_DIR/var/log/iwd"
install_etc etc/sv/iwd/run 755
install_etc etc/sv/iwd/log/run 755

# /etc/sv/bluetoothd/run — mismo caso que iwd: real, pero solo hace algo en
# hardware físico con adaptador Bluetooth.
mkdir -p "$ROOTFS_DIR/etc/sv/bluetoothd/log" "$ROOTFS_DIR/var/log/bluetoothd"
install_etc etc/sv/bluetoothd/run 755
install_etc etc/sv/bluetoothd/log/run 755

# Preparar directorios SSH vacíos. NUNCA se hornean claves del $HOME de quien
# compila: eso filtraría acceso root a toda imagen distribuida. Si se quiere
# una clave por defecto, pasar MIKEOS_SSH_AUTHORIZED_KEYS_FILE=<ruta> al build.
mkdir -p "$ROOTFS_DIR/root/.ssh" "$ROOTFS_DIR/home/mike/.ssh"
chmod 700 "$ROOTFS_DIR/root/.ssh" "$ROOTFS_DIR/home/mike/.ssh"
: > "$ROOTFS_DIR/root/.ssh/authorized_keys"
: > "$ROOTFS_DIR/home/mike/.ssh/authorized_keys"
if [ -n "${MIKEOS_SSH_AUTHORIZED_KEYS_FILE:-}" ] && [ -f "$MIKEOS_SSH_AUTHORIZED_KEYS_FILE" ]; then
    cat "$MIKEOS_SSH_AUTHORIZED_KEYS_FILE" >> "$ROOTFS_DIR/root/.ssh/authorized_keys"
    cat "$MIKEOS_SSH_AUTHORIZED_KEYS_FILE" >> "$ROOTFS_DIR/home/mike/.ssh/authorized_keys"
fi
chmod 600 "$ROOTFS_DIR/root/.ssh/authorized_keys" "$ROOTFS_DIR/home/mike/.ssh/authorized_keys"

# Habilitar servicios por defecto en /var/service
for s in console syslog network dropbear seatd dbus-system iwd bluetoothd; do
    ln -sf "/etc/sv/$s" "$ROOTFS_DIR/var/service/$s"
done

# Copiar kernel compilado en /boot de rootfs para gestión de MPM
if [ -f "$KERNEL_IMAGE" ]; then
    cp "$KERNEL_IMAGE" "$ROOTFS_DIR/boot/vmlinuz"
fi

# ------------------------------------------------------------------------------
# Runit Stages & Init Wrapper
# ------------------------------------------------------------------------------
# /init
install_etc init 755

# /etc/runit/1
install_etc etc/runit/1 755

# /etc/runit/2
install_etc etc/runit/2 755

# /etc/runit/3
install_etc etc/runit/3 755

# /etc/runit/ctrlaltdel
install_etc etc/runit/ctrlaltdel 755

# ------------------------------------------------------------------------------
# 8. Empaquetar Initramfs y Disco Persistente
# ------------------------------------------------------------------------------
echo "=== [8/8] Generando imagen initramfs.cpio.gz y disco persistente mikeos.img ==="
cd "$ROOTFS_DIR"
# Orden estable (LC_ALL=C) y gzip -n (sin timestamp/nombre embebido) para que
# dos builds del mismo árbol produzcan un initramfs.cpio.gz idéntico byte a
# byte, en vez de depender del orden de directorio del filesystem.
# mismo problema de propiedad que create-disk.sh: sin fakeroot, cpio empaqueta
# el UID de quien compila (mike) en vez de root para /etc/shadow y compañía.
fakeroot -- env ROOTFS_DIR="$ROOTFS_DIR" ISO_DIR="$ISO_DIR" sh -c '
    set -e
    chown -R root:root "$ROOTFS_DIR"
    [ -d "$ROOTFS_DIR/home/mike" ] && chown -R 1000:1000 "$ROOTFS_DIR/home/mike"
    chmod 4755 "$ROOTFS_DIR/bin/busybox"
    chmod 4755 "$ROOTFS_DIR/usr/bin/m-sudo"
    cd "$ROOTFS_DIR"
    find . -not -path "./boot/*" -not -path "./var/lib/mpm/repo/*" -not -path "./usr/lib/*" -not -path "./lib64/*" -not -path "./usr/share/X11/*" -not -path "./usr/bin/Hyprland*" -not -path "./usr/bin/quickshell*" -print0 \
        | LC_ALL=C sort -z \
        | cpio --null -o --format=newc 2>/dev/null \
        | gzip -9n > "$ISO_DIR/initramfs.cpio.gz"
'

chmod +x "$PROJECT_ROOT/scripts/create-disk.sh"
"$PROJECT_ROOT/scripts/create-disk.sh"

echo ""
echo "================================================================"
echo " ¡MIKE OS Construido con Éxito (Core Consolidado)!"
echo " Initramfs: $ISO_DIR/initramfs.cpio.gz ($(du -h "$ISO_DIR/initramfs.cpio.gz" | cut -f1))"
echo " Disco ext4: $ISO_DIR/mikeos.img ($(du -h "$ISO_DIR/mikeos.img" | cut -f1))"
echo " Para arrancar: ./scripts/run-qemu.sh"
echo "================================================================"
