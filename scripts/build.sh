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

# El kernel se recompila si no está, y TAMBIÉN si el fragmento de opciones ha
# cambiado desde la última vez. Antes sólo se miraba si el binario existía: se
# podía editar .config, reconstruir el sistema entero y seguir arrancando el
# kernel viejo sin que nada avisara. Así estuvo un fallo de consola gráfica sin
# corregirse aunque la opción ya estaba puesta en el archivo.
KERNEL_HUELLA="$PROJECT_ROOT/kernel/.mikeos-config-sha"
KERNEL_SHA_AHORA="$(sha256sum "$KERNEL_CONFIG_FRAGMENT" 2>/dev/null | cut -d' ' -f1)"
KERNEL_SHA_ANTES="$(cat "$KERNEL_HUELLA" 2>/dev/null || true)"
if [ -f "$KERNEL_IMAGE" ] && [ "$KERNEL_SHA_AHORA" != "$KERNEL_SHA_ANTES" ]; then
    echo "Las opciones del kernel han cambiado: hay que recompilarlo."
    rm -f "$KERNEL_IMAGE"
fi

# --- Firmware DENTRO del kernel ---------------------------------------------
#
# Esto es lo que hace que arranque el escritorio en una Surface Laptop 4.
#
# amdgpu va compilado dentro del kernel (=y), así que arranca mientras el
# kernel se inicializa. En ese momento pide su firmware al sistema de archivos
# y, en la Surface, se lo encontró ausente aunque estuviera perfectamente en el
# initramfs:
#
#   amdgpu 0000:03:00.0: Direct firmware load for amdgpu/renoir_sdma.bin failed with error -2
#   amdgpu 0000:03:00.0: early_init of IP block <sdma_v4_0> failed -19
#   amdgpu 0000:03:00.0: Fatal error during GPU init
#
# Sin GPU, lo único que queda es el framebuffer de la firmware, y con eso no
# hay escritorio: sólo una consola. Perseguir POR QUÉ el kernel no ve un
# archivo que está ahí es perseguir una carrera entre el arranque del driver y
# el montaje de la raíz, y esa carrera no se gana: se elimina.
#
# CONFIG_EXTRA_FIRMWARE mete estos archivos DENTRO del binario del kernel. A
# partir de ahí amdgpu no tiene que leer nada de ningún disco, así que da igual
# qué esté montado y cuándo. Son las familias de APU de portátil AMD que
# existen: 5,5 MB en un kernel de 23. El resto del firmware sigue viajando como
# archivos, que es lo correcto para lo que se carga más tarde (wifi, sonido).
FW_EMPOTRADO_DIR="$PROJECT_ROOT/build/firmware-kernel"
FW_EMPOTRADO=""
if [ -d /lib/firmware/amdgpu ]; then
    mkdir -p "$FW_EMPOTRADO_DIR/amdgpu"
    for _fam in renoir green_sardine picasso raven raven2; do
        for _f in /lib/firmware/amdgpu/${_fam}_*; do
            [ -e "$_f" ] || continue
            _base="$(basename "$_f")"
            _base="${_base%.zst}"
            if [ ! -f "$FW_EMPOTRADO_DIR/amdgpu/$_base" ]; then
                case "$_f" in
                    *.zst) zstd -dqf "$_f" -o "$FW_EMPOTRADO_DIR/amdgpu/$_base" 2>/dev/null || continue ;;
                    *)     cp -a "$_f" "$FW_EMPOTRADO_DIR/amdgpu/$_base" 2>/dev/null || continue ;;
                esac
            fi
            FW_EMPOTRADO="$FW_EMPOTRADO amdgpu/$_base"
        done
    done
fi
# La huella incluye la lista: si cambia el firmware que se empotra, hay que
# recompilar el kernel aunque el fragmento de opciones no se haya tocado.
PARCHES_SHA="$(cat "$PROJECT_ROOT"/build/kernel-patches/*.patch 2>/dev/null | sha256sum | cut -d' ' -f1)"
KERNEL_SHA_AHORA="$(printf '%s%s%s' "$KERNEL_SHA_AHORA" "$FW_EMPOTRADO" "$PARCHES_SHA" | sha256sum | cut -d' ' -f1)"
if [ -f "$KERNEL_IMAGE" ] && [ "$KERNEL_SHA_AHORA" != "$KERNEL_SHA_ANTES" ]; then
    rm -f "$KERNEL_IMAGE"
fi

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

    # Parches de hardware Surface (ver build/kernel-patches/LEEME.md).
    #
    # Se aplican sobre el árbol recién sacado, así que primero se deshace
    # cualquier cosa que dejara una compilación anterior: aplicar dos veces el
    # mismo parche falla, y el fallo parecería del parche y no del estado.
    #
    # Hacen falta las dos órdenes. "git checkout" devuelve los archivos que ya
    # existían, pero varios de estos parches CREAN archivos nuevos
    # (drivers/rtc/rtc-surface.c y compañía), y esos no los toca: se quedan, y
    # el parche siguiente muere con "already exists in working directory".
    # "git clean -fd" sin "-x" barre justo esos, y respeta lo ignorado, o sea
    # que no se lleva por delante .config ni los objetos ya compilados.
    git checkout -q -- . 2>/dev/null || true
    git clean -qfd 2>/dev/null || true
    if [ -d "$PROJECT_ROOT/build/kernel-patches" ]; then
        for _parche in "$PROJECT_ROOT"/build/kernel-patches/*.patch; do
            [ -f "$_parche" ] || continue
            if git apply "$_parche"; then
                echo "  parche aplicado: $(basename "$_parche")"
            else
                # Plantarse, no seguir. Un parche que no entra en silencio da
                # un kernel que parece bueno y no lo es, y el fallo aparece
                # semanas después en un portátil concreto.
                echo "ERROR: no se pudo aplicar $(basename "$_parche")." >&2
                echo "       El kernel ha cambiado y el parche necesita revisión." >&2
                exit 1
            fi
        done
    fi

    make defconfig
    ./scripts/kconfig/merge_config.sh -m .config "$KERNEL_CONFIG_FRAGMENT"
    # La lista de firmware a empotrar se calcula arriba, así que no puede vivir
    # en el fragmento: se añade aquí, después de mezclarlo.
    if [ -n "$FW_EMPOTRADO" ]; then
        _lista="$(echo "$FW_EMPOTRADO" | sed 's/^ *//')"
        echo "Empotrando en el kernel: $(echo "$_lista" | wc -w) archivos de firmware de gráficas AMD."
        {
            echo "CONFIG_EXTRA_FIRMWARE=\"$_lista\""
            echo "CONFIG_EXTRA_FIRMWARE_DIR=\"$FW_EMPOTRADO_DIR\""
        } >> .config
    fi
    make olddefconfig
    make -j"$(nproc)" bzImage
    cd "$PROJECT_ROOT"
    printf '%s\n' "$KERNEL_SHA_AHORA" > "$KERNEL_HUELLA"
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

# m-autenticar: comprueba una contraseña contra /etc/shadow, que sólo root
# puede leer. Lo necesita la pantalla de bloqueo, que corre como el usuario.
# También setuid-root, y por el mismo motivo estático que m-sudo.
gcc -O2 -static -Wall "$PROJECT_ROOT/build/mcore/m-autenticar-src.c" -o "$BUILD_DIR/mcore/m-autenticar"

# m-colores: saca la paleta del sistema de una imagen. Se enlaza con GdkPixbuf
# -- no estático, porque GdkPixbuf carga sus lectores de imagen con dlopen y
# un binario estático no puede -- y esa biblioteca ya viaja dentro del sistema
# para la ventana de bienvenida y el selector de fondos.
gcc -O2 -Wall "$PROJECT_ROOT/build/mcore/m-colores-src.c" -o "$BUILD_DIR/mcore/m-colores" \
    $(pkg-config --cflags --libs gdk-pixbuf-2.0) -lm


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
# fastfetch lo copia el resolutor de bibliotecas junto al resto del escritorio
# (ver la lista "bins" más abajo), que es quien le lleva sus dependencias. La
# comprobación de que llegó está después de ese paso, no aquí: preguntar antes
# de copiarlo daba un aviso falso en cada build.

# Instalar MCore
for util in m-service m-system m-network m-user m-disk m-info m-doctor m-log m-sudo m-autenticar m-clave m-acceso-remoto m-colores m-particiones m-brillo m-tapa m-install m-screenshot m-volume m-metrics m-audio-setup m-fastfetch m-workspace-cycle m-drivers m-wifi m-bluetooth m-wallhaven m-fondo m-internet; do
    cp "$BUILD_DIR/mcore/$util" "$ROOTFS_DIR/usr/bin/"
    chmod 755 "$ROOTFS_DIR/usr/bin/$util"
done
# GRUB para los discos instalados.
#
# Se construye AQUÍ, en el equipo que compila, y viaja dentro del sistema como
# un archivo más. m-install no lo genera: sólo lo copia a la partición EFI.
# Es a propósito -- grub-mkstandalone forma parte del paquete grub, que no está
# ni tiene por qué estar dentro de MIKE OS, así que generarlo en el momento de
# instalar significaría que la instalación falla en cualquier equipo donde no
# esté. Un archivo ya hecho no puede faltar.
#
# La configuración empotrada no es el menú: es el trampolín que busca el menú
# de verdad en la partición EFI (ver build/grub/grub.cfg.arranque). El menú lo
# escribe m-install cuando ya conoce el UUID del disco.
if command -v grub-mkstandalone >/dev/null 2>&1; then
    mkdir -p "$ROOTFS_DIR/usr/share/mikeos/grub"
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="$ROOTFS_DIR/usr/share/mikeos/grub/grubx64.efi" \
        --modules="part_gpt part_msdos fat ext2 btrfs normal linux echo all_video search search_label search_fs_uuid search_fs_file configfile gfxterm gfxmenu serial terminal test sleep halt reboot png video video_fb font loadenv" \
        "boot/grub/grub.cfg=$PROJECT_ROOT/build/grub/grub.cfg.arranque" \
        $(cd "$PROJECT_ROOT/build/grub/tema" 2>/dev/null && for _t in *; do printf '%s ' "boot/grub/tema/$_t=$PROJECT_ROOT/build/grub/tema/$_t"; done) 2>/dev/null \
        && echo "  -> GRUB de disco: $(du -h "$ROOTFS_DIR/usr/share/mikeos/grub/grubx64.efi" | cut -f1)"
    # El tema también suelto, porque el menú que escribe m-install vive en la
    # partición EFI y lee sus imágenes de allí, no del disco en memoria.
    cp -r "$PROJECT_ROOT/build/grub/tema" "$ROOTFS_DIR/usr/share/mikeos/grub/tema"
else
    echo "  AVISO: sin grub-mkstandalone; los discos instalados arrancarán sólo por EFI stub."
fi

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

# El repositorio oficial viene configurado de fábrica. Sin esto, un sistema
# recién instalado no sabe dónde buscar actualizaciones y hay que escribir un
# "mpm source add" que nadie adivina: en la práctica, nadie se actualizaría
# nunca. Configurado no significa automático -- sigue haciendo falta pedir el
# "mpm upgrade" a mano, que es como debe ser.
MIKEOS_REPO_OFICIAL="${MIKEOS_REPO_OFICIAL:-https://m1keos.duckdns.org/mpm/}"
cat > "$ROOTFS_DIR/var/lib/mpm/sources.list" <<EOF
# Repositorios que consulta "mpm update".
# Añadir otro:  mpm source add <url>
$MIKEOS_REPO_OFICIAL
EOF
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
bins = ['/usr/bin/Hyprland', '/usr/bin/Xwayland', '/usr/bin/start-hyprland', '/usr/bin/hyprctl', '/usr/bin/quickshell', '/usr/bin/fuzzel', '/usr/bin/seatd', '/usr/bin/seatd-launch', '/usr/bin/swaybg', '/usr/bin/bwrap', '/usr/bin/wpctl', '/usr/bin/pactl', '/usr/bin/amixer', '/usr/bin/grim', '/usr/bin/slurp', '/usr/bin/wl-copy', '/usr/bin/pipewire', '/usr/bin/pipewire-pulse', '/usr/bin/wireplumber', '/usr/bin/dbus-daemon', '/usr/bin/dbus-launch', '/usr/bin/dbus-run-session', '/usr/bin/zstd', '/usr/bin/unzstd', '/usr/bin/iwctl', '/usr/bin/bluetoothctl', f'{build_dir}/mterminal/m-terminal', f'{build_dir}/settings/m-settings', f'{build_dir}/settings/m-wallpapers', f'{build_dir}/settings/m-welcome',
    # Herramientas de disco. Hacen falta para que el instalador pueda crear
    # una instalación que arranque de verdad: tabla GPT (sfdisk), partición
    # EFI en FAT32 (mkfs.vfat) y raíz en btrfs (mkfs.btrfs, btrfs). BusyBox
    # no trae ninguna de las tres, así que hasta ahora m-install sólo sabía
    # formatear el disco entero en ext4 y sin tabla de particiones -- algo
    # que en un portátil UEFI no arranca.
    '/usr/bin/mkfs.btrfs', '/usr/bin/btrfs', '/usr/bin/btrfstune',
    '/usr/bin/mkfs.vfat', '/usr/bin/fatlabel',
    '/usr/bin/sfdisk', '/usr/bin/partx', '/usr/bin/blkid', '/usr/bin/lsblk',
    '/usr/bin/mkfs.ext4', '/usr/bin/e2label', '/usr/bin/findmnt',
    '/usr/bin/efibootmgr',
    # Herramientas de particionado de verdad. Hasta ahora el USB sólo llevaba
    # sfdisk y los mkfs, lo justo para "borrar el disco entero y empezar de
    # cero". Con esto se puede además mirar qué hay ya en un disco, encogerlo
    # para hacer sitio, y comprobar que no vamos a romper nada antes de tocar.
    #
    #   parted      lee y modifica tablas de particiones de cualquier tipo.
    #               Durante un tiempo NO se pudo incluir: necesitaba símbolos
    #               de la libudev de systemd que libudev-zero no trae, y se
    #               caía con "undefined symbol: udev_queue_unref". Se arregló
    #               añadiendo esa familia de funciones (build/libudev/).
    #   resize2fs   encoge y agranda ext4 (hace falta para instalar al lado)
    #   e2fsck      obligatorio ANTES de encoger ext4; resize2fs se niega si no
    #   dumpe2fs    cuánto ocupa de verdad un ext4, para saber hasta dónde cabe
    #   ntfs-3g     monta NTFS, que es como se reconoce un Windows instalado
    #
    #   ntfsresize  encoge NTFS: es lo que permite quitarle sitio a Windows
    #               para instalar al lado. Va en el paquete ntfsprogs del
    #               equipo que compila; si no está, el build sigue y lo único
    #               que se pierde es poder encoger Windows (instalar en
    #               espacio libre sigue funcionando).
    #   ntfsfix     repara un NTFS que Windows dejó a medias. Sin esto,
    #               ntfsresize se niega a tocarlo -- y con razón.
    '/usr/bin/parted', '/usr/bin/resize2fs', '/usr/bin/e2fsck',
    '/usr/bin/dumpe2fs', '/usr/bin/ntfs-3g', '/usr/bin/ntfs-3g.probe',
    '/usr/bin/lowntfs-3g', '/usr/bin/ntfsresize', '/usr/bin/ntfsinfo',
    '/usr/bin/ntfsfix', '/usr/bin/ntfsclone', '/usr/bin/mkntfs',
    # fastfetch. Estaba escrito el código para copiarlo desde
    # build/fastfetch-static/, pero NADA lo compilaba nunca: esa carpeta no
    # existe, así que el build avisaba «Fastfetch no fue compilado» y seguía.
    # Resultado: la terminal abría sin la ficha del sistema y m-info caía a su
    # versión de respaldo. Se copia del equipo de construcción con sus
    # bibliotecas, igual que el resto del escritorio.
    '/usr/bin/fastfetch']
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
#
# 'imageformats' no estaba, y de ahí que el selector de fondos saliera con
# veinticinco rectángulos vacíos para siempre. Qt trae PNG dentro de QtGui,
# pero JPEG, WEBP y los demás van en plugins aparte; las miniaturas de
# Wallhaven son .jpg, así que se descargaban bien (estaban en la caché) y
# luego no había quien las dibujara. El fallo no dice nada por ninguna parte:
# el Image se queda en estado Error y ya.
for plug_dir in ['platforms', 'wayland-shell-integration', 'wayland-graphics-integration-client', 'platforminputcontexts', 'imageformats', 'iconengines']:
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
    # /lib/firmware queda fuera pase lo que pase. Algunos blobs de firmware
    # son ELF por dentro (los de la GPU, entre otros) y "strip" los daría por
    # buenos y les quitaría secciones que el dispositivo necesita: el
    # resultado es una gráfica o una WiFi que no arranca, y el motivo no se
    # ve por ninguna parte.
    if '/lib/firmware' in r_root:
        r_dirs[:] = []
        continue
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

if [ ! -x "$ROOTFS_DIR/usr/bin/fastfetch" ]; then
    echo "Aviso: no hay fastfetch en la imagen; la terminal abrirá sin la ficha" >&2
    echo "       del sistema y m-info usará su versión de respaldo." >&2
fi

echo "Copiando firmware de hardware real..."
# ---------------------------------------------------------------------------
# FIRMWARE
#
# Hasta ahora /lib/firmware no existía siquiera. Da igual tener el driver de
# la gráfica o del WiFi compilado: la mayoría del hardware moderno no arranca
# con el driver solo, necesita además un binario que el kernel le carga al
# encenderlo. Sin esta carpeta, en una Surface no hay ni gráficos ni red.
#
# No se copia /lib/firmware entero (534 MiB en el equipo de construcción):
# sólo lo que estas máquinas piden de verdad. La lista se amplía cuando haga
# falta, y "m-drivers" ya sabe decir qué falta en un equipo concreto.
#
# El anfitrión los guarda comprimidos con zstd (*.bin.zst). El kernel sólo
# sabe leerlos así con CONFIG_FW_LOADER_COMPRESS, que no está, de modo que se
# descomprimen al copiarlos. Ocupan más y se cargan más rápido.
# ---------------------------------------------------------------------------
FW_ORIGEN="/lib/firmware"
FW_DESTINO="$ROOTFS_DIR/lib/firmware"
if [ -d "$FW_ORIGEN" ]; then
    mkdir -p "$FW_DESTINO"
    # La regla para decidir qué entra y qué no:
    #
    #   Si sin ese firmware el equipo se queda SIN PANTALLA, entra. De todo lo
    #   demás se puede salir: sin wifi se puede enchufar un cable, sin sonido
    #   se puede trabajar, sin bluetooth también. Sin imagen no se puede ni
    #   leer el error, que es exactamente lo que le pasó a una Surface Laptop 4
    #   con una versión que llevaba el driver pero no su firmware.
    #
    # GRÁFICAS: todo lo que lleve un portátil de los últimos diez años.
    #   picasso, raven          Ryzen 2000-3000 (Surface Laptop 3 AMD)
    #   renoir, green_sardine   Ryzen 4000-5000 (Surface Laptop 4 AMD)
    #   yellow_carp             Ryzen 6000 (Rembrandt)
    #   vangogh, cezanne,       Ryzen 5000-7000 de portátil. Se añadieron
    #   rembrandt, phoenix      después de que una Surface Laptop 4 arrancara
    #                           sin escritorio: el firmware de SU generación sí
    #                           estaba, pero acertar la familia exacta de cada
    #                           portátil AMD a base de lista es perder siempre.
    #                           Son 11 MB más y cubren todas las APU de
    #                           portátil de los últimos cinco años.
    #   dcn*, psp_1*            Los nombres nuevos del motor de pantalla y del
    #                           procesador de seguridad. En las generaciones
    #                           recientes el firmware ya no se llama por el
    #                           nombre de la APU sino por el de su bloque.
    #   vega10, vega20          tarjetas dedicadas. El comentario de antes
    #                           decía que estaban incluidas y NO lo estaban:
    #                           la lista no las nombraba por ninguna parte.
    #   i915                    Intel. La versión anterior lo dejaba fuera
    #                           diciendo que eran 28 MB; son 9,6. Sin él,
    #                           cualquier portátil Intel se queda a oscuras
    #                           igual que se quedó la Surface.
    #
    # De iwlwifi entra SÓLO la familia "cc-a0", que es la que lleva la Surface
    # Laptop 4 (lo pidió por su nombre: "Direct firmware load for
    # iwlwifi-cc-a0-77.ucode failed"). Son 3 MB de los 239 que ocupa iwlwifi
    # entero, así que ese equipo tiene wifi sin cargar con el resto. Y con
    # ellos el Bluetooth de Intel (ibt-19/20), que también se quejaba.
    #
    # El resto de iwlwifi sigue fuera a propósito y es un compromiso incómodo: Se instala con "mpm install firmware-extra"... para
    # lo cual hace falta red. O sea que en un portátil con wifi Intel y sin
    # cable, la primera vez hay que tirar de móvil por USB. Está documentado en
    # m-drivers, que dice exactamente qué falta y cómo traerlo.
    FW_PATRONES="
        amdgpu/*
        i915/*            xe/*
        ath10k/*          ath11k/*          ath12k/*
        qca/*             ath9k_htc/*
        mediatek/mt76*    mediatek/WIFI_*
        rtw88/*           rtw89/*           rtlwifi/*         rtl_nic/*
        brcm/*
        mrvl/*
        intel/ibt-*       qca/*bt*
        amd-ucode/*       intel-ucode/*
        regulatory.db*
        rtl_bt/*
    "
    _fw_n=0
    for _pat in $FW_PATRONES; do
        for _f in $FW_ORIGEN/$_pat; do
            [ -e "$_f" ] || continue
            [ -d "$_f" ] && continue
            _rel="${_f#$FW_ORIGEN/}"
            # Se copian TAL CUAL, comprimidos incluidos. El kernel lleva
            # CONFIG_FW_LOADER_COMPRESS_ZSTD, así que sabe abrirlos él mismo.
            # Antes se descomprimían "porque se cargan más rápido": eran unos
            # milisegundos a cambio de triplicar el espacio, y ese espacio es
            # exactamente lo que impedía cubrir más hardware.
            mkdir -p "$FW_DESTINO/$(dirname "$_rel")"
            cp -aL "$_f" "$FW_DESTINO/$_rel" 2>/dev/null || continue
            _fw_n=$((_fw_n + 1))
        done
    done
    # iwlwifi (Intel) no va en la imagen base: son 185 archivos y cada serie
    # tiene varias revisiones -- 239 MB en total para un portátil que lleva
    # Qualcomm. Va en el paquete firmware-extra, que se instala en un minuto
    # si hace falta.
    # --- Intel Wi-Fi: las dos revisiones más nuevas de cada familia ---------
    #
    # iwlwifi entero son 44 familias por hasta diez revisiones cada una: 92 MB
    # para cubrir hardware que ya nadie tiene. El kernel pide la revisión más
    # alta que entienda y va bajando, así que con las dos últimas de cada
    # familia se cubre cualquier kernel reciente en un tercio del espacio.
    #
    # Esto no se puede expresar con un patrón de archivos, de ahí el bloque
    # aparte. La Wi-Fi de la Surface Laptop 4 (AX200, familia "cc-a0") sale de
    # aquí.
    if [ -d "$FW_ORIGEN/intel/iwlwifi" ]; then
        mkdir -p "$FW_DESTINO/intel/iwlwifi"
        _iwl=0
        for _fam in $(ls "$FW_ORIGEN/intel/iwlwifi" 2>/dev/null \
                      | sed -n 's/^\(iwlwifi-.*\)-[0-9][0-9]*\.ucode.*/\1/p' | sort -u); do
            for _f in $(ls "$FW_ORIGEN/intel/iwlwifi/$_fam"-*.ucode* 2>/dev/null \
                        | sed 's/.*-\([0-9][0-9]*\)\.ucode/\1 &/' | sort -rn | head -2 | cut -d' ' -f2-); do
                [ -e "$_f" ] || continue
                cp -aL "$_f" "$FW_DESTINO/intel/iwlwifi/$(basename "$_f")" 2>/dev/null || continue
                _iwl=$((_iwl + 1))
                _fw_n=$((_fw_n + 1))
            done
        done
        # El kernel las pide por su nombre a secas, sin la carpeta.
        for _f in "$FW_DESTINO/intel/iwlwifi"/*; do
            [ -f "$_f" ] || continue
            ln -sf "intel/iwlwifi/$(basename "$_f")" "$FW_DESTINO/$(basename "$_f")" 2>/dev/null || true
        done
        echo "  -> $_iwl archivos de Wi-Fi Intel (2 revisiones por familia)."
    fi

    # --- NVIDIA: lo pequeño sí, los blobs gigantes no ----------------------
    #
    # nouveau necesita un firmware por chip (4 MB en total, entra sin
    # discusión) y, de Turing en adelante, además el "GSP": 112 MB que
    # triplicarían el tamaño de la imagen para cubrir un caso en el que casi
    # siempre hay una gráfica integrada moviendo la pantalla. Ese va aparte,
    # con "mpm install linux-firmware-nvidia".
    if [ -d "$FW_ORIGEN/nvidia" ]; then
        _nv=0
        for _d in "$FW_ORIGEN"/nvidia/*/; do
            [ -d "$_d" ] || continue
            case "$(basename "$_d")" in
                ga102|tu102|[0-9]*) continue ;;   # los de GSP, fuera
            esac
            for _f in "$_d"*; do
                [ -f "$_f" ] || continue
                _rel="${_f#$FW_ORIGEN/}"
                mkdir -p "$FW_DESTINO/$(dirname "$_rel")"
                cp -aL "$_f" "$FW_DESTINO/$_rel" 2>/dev/null || continue
                _nv=$((_nv + 1)); _fw_n=$((_fw_n + 1))
            done
        done
        echo "  -> $_nv archivos de NVIDIA (sin los blobs GSP, que van aparte)."
    fi

    echo "  -> $_fw_n archivos de firmware ($(du -sh "$FW_DESTINO" 2>/dev/null | cut -f1))."
else
    echo "Aviso: el equipo de construcción no tiene /lib/firmware; la imagen"
    echo "       saldrá sin firmware y no habrá gráficos ni WiFi en hardware real."
fi

echo "Preparando compatibilidad libudev..."
# libudev-zero es opcional: un fallo de red no debe dejar el sistema sin
# imagen. Si ya copiamos libudev del host, se conserva como fallback.
LIBUDEV_ZERO_DIR="${TMPDIR:-/tmp}/mikeos-libudev-zero"
LIBUDEV_ZERO_COMMIT="7a6eee2db11f2eb0f7fd065ae9597fcd270e6734"
if [ ! -d "$LIBUDEV_ZERO_DIR" ]; then
    ( git clone https://github.com/illiliti/libudev-zero.git "$LIBUDEV_ZERO_DIR" >/dev/null 2>&1 && \
      cd "$LIBUDEV_ZERO_DIR" && git checkout -q "$LIBUDEV_ZERO_COMMIT" ) || true
fi
# libudev-zero no trae la familia udev_queue_* -- describe la cola de un
# demonio udev que aquí no existe -- y sin ella libdevmapper no enlaza, así que
# parted se cae nada más arrancar y con él GParted y todo lo que lo use por
# debajo. build/libudev/udev_queue.c la añade; ver su cabecera para el porqué
# de cada respuesta. Se copia dentro del árbol clonado y se añade al Makefile.
if [ -d "$LIBUDEV_ZERO_DIR" ] && [ -f "$PROJECT_ROOT/build/libudev/udev_queue.c" ]; then
    cp "$PROJECT_ROOT/build/libudev/udev_queue.c" "$LIBUDEV_ZERO_DIR/"
    if ! grep -q "udev_queue.o" "$LIBUDEV_ZERO_DIR/Makefile"; then
        sed -i 's|^OBJ = \\|OBJ = \\\n\t  udev_queue.o \\|' "$LIBUDEV_ZERO_DIR/Makefile"
    fi

    # Las funciones nuevas, al mapa de símbolos.
    if ! grep -q "udev_queue_new" "$LIBUDEV_ZERO_DIR/libudev.sym"; then
        sed -i 's|^global:|global:\n\tudev_queue_new;\n\tudev_queue_ref;\n\tudev_queue_unref;\n\tudev_queue_get_udev;\n\tudev_queue_get_udev_is_active;\n\tudev_queue_get_queue_is_empty;\n\tudev_queue_get_kernel_seqnum;\n\tudev_queue_get_udev_seqnum;\n\tudev_queue_get_seqnum_is_finished;\n\tudev_queue_get_seqnum_sequence_is_finished;\n\tudev_queue_get_queued_list_entry;\n\tudev_queue_get_fd;\n\tudev_queue_flush;|' \
            "$LIBUDEV_ZERO_DIR/libudev.sym"
    fi

    # Y que el enlazador lo use. El Makefile de libudev-zero trae el mapa pero
    # no lo aplica, así que la biblioteca salía con los símbolos SIN versión.
    # Funcionaba -- glibc los acepta -- pero soltaba un
    #   "libudev.so.1: no version information available"
    # en cada arranque de parted, que asusta sin motivo. Con el mapa aplicado,
    # los símbolos salen como LIBUDEV_183, que es lo que piden los binarios.
    if ! grep -q "version-script" "$LIBUDEV_ZERO_DIR/Makefile"; then
        sed -i 's|-Wl,-soname,libudev.so.1|-Wl,-soname,libudev.so.1 -Wl,--version-script=libudev.sym|' \
            "$LIBUDEV_ZERO_DIR/Makefile"
    fi
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
# La versión vive en un solo sitio, el archivo VERSION de la raíz del
# proyecto, y se sustituye aquí. Antes estaba escrita a mano en os-release y
# en tres puntos más del QML, así que publicar una versión nueva significaba
# acordarse de cuatro archivos: el Centro de Control siguió diciendo 0.2.0
# durante toda la 0.3.0.
MIKEOS_VERSION="$(tr -d ' \n' < "$PROJECT_ROOT/VERSION" 2>/dev/null || echo 0.0.0)"
sed -i "s/@VERSION@/$MIKEOS_VERSION/g" "$ROOTFS_DIR/etc/os-release"

# Configurar skeleton /etc/skel y ~/.config/mike
mkdir -p "$ROOTFS_DIR/etc/skel/.config/mike/quickshell" "$ROOTFS_DIR/etc/skel/.config/mike/theme"
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
cp "$BUILD_DIR/desktop/start-mike-desktop" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/desktop/m-panel" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/desktop/m-bloquear" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/desktop/m-instalador" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/desktop/m-arranque-instalar" "$ROOTFS_DIR/usr/bin/"
cp "$BUILD_DIR/mcore/m-reintentar-drivers" "$ROOTFS_DIR/usr/bin/"
chmod +x "$ROOTFS_DIR/usr/bin/m-reintentar-drivers"
cp "$BUILD_DIR/mcore/m-discos-permisos" "$ROOTFS_DIR/usr/bin/"
chmod +x "$ROOTFS_DIR/usr/bin/m-discos-permisos"

# Apagar y reiniciar.
#
# Van en /usr/bin, que en el PATH está ANTES que /sbin, así que estos ganan a
# los applets de BusyBox -- que bajo runit no hacían absolutamente nada (ver
# m-apagado). No se toca /sbin: si alguien lo llama por ruta completa, sigue
# encontrando lo de siempre.
cp "$BUILD_DIR/mcore/m-apagado" "$ROOTFS_DIR/usr/bin/"
chmod +x "$ROOTFS_DIR/usr/bin/m-apagado"
for _acc in reboot poweroff halt shutdown; do
    ln -sf m-apagado "$ROOTFS_DIR/usr/bin/$_acc"
done
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
    # m-autenticar lee /etc/shadow para la pantalla de bloqueo. Sin el bit
    # setuid no puede, y el bloqueo rechazaría hasta la contraseña correcta.
    chmod 4755 "$ROOTFS_DIR/usr/bin/m-autenticar"
    cd "$ROOTFS_DIR"
    # /lib/firmware queda fuera del initramfs, MENOS el de las tarjetas
    # gráficas. El initramfs se carga entero en memoria antes de que exista
    # nada, así que cada mega ahí es memoria y tiempo de arranque: meterlo todo
    # lo subía de 26 MB a 142 MB, y en un equipo de 512 MB eso es la diferencia
    # entre arrancar y no arrancar. Por eso la regla general es dejarlo fuera.
    #
    # Pero el de la GPU es distinto, y costó caro descubrirlo. amdgpu, i915 y
    # compañía van compilados DENTRO del kernel (=y), así que arrancan mientras
    # el kernel se inicializa: antes de que exista ninguna raíz que montar. Si
    # su firmware no está en el initramfs, no lo encuentran, el driver no carga
    # y el equipo se queda SIN NINGUNA IMAGEN. Ni escritorio, ni mensajes, ni
    # un error: la pantalla se queda como la dejó GRUB.
    #
    # Le pasó a una Surface Laptop 4 (Ryzen 4000, gráfica Renoir): arrancaba
    # bien pero a ciegas, y desde fuera parecía colgada. En una máquina virtual
    # no se ve nunca, porque el driver de la GPU virtual no necesita firmware.
    #
    # Entra el de TODAS las gráficas (amdgpu, i915, xe, nvidia), no sólo el de
    # AMD: el argumento vale igual para las demás.
    #
    # El resto -- wifi, bluetooth, sonido -- se queda fuera, y ahora eso ya no
    # cuesta nada: m-reintentar-drivers vuelve a probar esos dispositivos en
    # cuanto la raíz de verdad está montada, así que encuentran su firmware un
    # segundo más tarde en vez de quedarse sin él para siempre. Antes ese
    # segundo era la diferencia entre tener wifi y no tenerla.
    find . -not -path "./boot/*" -not -path "./var/lib/mpm/repo/*" -not -path "./usr/lib/*" -not -path "./lib64/*" -not -path "./usr/share/X11/*" -not -path "./usr/bin/Hyprland*" -not -path "./usr/bin/quickshell*" \
         \( -path "./lib/firmware/amdgpu/*" -o -path "./lib/firmware/i915/*" \
            -o -path "./lib/firmware/xe/*" -o -path "./lib/firmware/nvidia/*" \
            -o -path "./lib/firmware/radeon/*" -o -not -path "./lib/firmware/*" \) -print0 \
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
