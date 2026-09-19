#!/bin/bash
# ¿Está el escritorio entero traducido?
#
# Por qué existe
# --------------
# El instalador lleva desde el primer día preguntando "Choose your language" y
# prometiendo debajo que se puede cambiar luego en el Centro de Control. Las
# dos cosas eran mentira. Al arreglarlo apareció el problema de verdad: una
# traducción se rompe en SILENCIO. Nadie ve un error; simplemente una frase
# sale en español en mitad de una ventana en inglés, y sólo se nota si alguien
# que habla inglés mira esa pantalla concreta.
#
# Esto compara, archivo por archivo, lo que se PINTA contra lo que está
# TRADUCIDO. No hace falta arrancar nada: son los fuentes.
#
#   ./tests/traducciones.sh
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

OK=0; MAL=0
verde() { printf '  \033[32m✓\033[0m %s\n' "$*"; OK=$((OK+1)); }
rojo()  { printf '  \033[31m✗\033[0m %s\n' "$*"; MAL=$((MAL+1)); }
titulo(){ printf '\n\033[1m%s\033[0m\n' "$*"; }

# --------------------------------------------------------------------------
titulo "m-idioma"

if [ "$(MIKEOS_LANG=en build/mcore/m-idioma)" = "en" ] \
&& [ "$(MIKEOS_LANG=es build/mcore/m-idioma)" = "es" ]; then
    verde "la variable de entorno manda sobre el archivo"
else
    rojo  "MIKEOS_LANG no se respeta"
fi

if [ "$(MIKEOS_LANG=klingon build/mcore/m-idioma)" = "es" ]; then
    verde "un idioma que no existe cae al de por defecto"
else
    rojo  "un idioma inválido no cae al de por defecto"
fi

# --------------------------------------------------------------------------
titulo "Escritorio (QML)"

FALTAN="$(python3 - <<'PY'
import io, re, glob, os
dic = io.open("build/desktop/quickshell/Idioma.qml", encoding="utf-8").read()
cuerpo = dic[dic.index("property var traducciones"):dic.index("function t(")]
claves = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)":', cuerpo, re.M))
malos = []
for f in sorted(glob.glob("build/desktop/quickshell/*.qml")):
    s = io.open(f, encoding="utf-8").read()
    for t in set(re.findall(r'Idioma\.t\("((?:[^"\\]|\\.)*)"\)', s)):
        if t not in claves:
            malos.append("%s: %s" % (os.path.basename(f), t))
for m in sorted(malos): print(m)
PY
)"
if [ -z "$FALTAN" ]; then
    verde "todo lo que se pinta está en el diccionario"
else
    rojo  "hay texto que se pinta y no está traducido:"
    printf "      %s\n" "$FALTAN"
fi

# El singleton tiene que estar declarado COMO singleton. Si qmldir lo declara
# como componente normal, QML crea una copia por cada uso: cada una lanza su
# propio "m-idioma" y el valor deja de ser compartido, así que cambiar el
# idioma en el Centro de Control no movería ni la barra ni el bloqueo.
if grep -q '^singleton Idioma ' build/desktop/quickshell/qmldir; then
    verde "Idioma está declarado como singleton en qmldir"
else
    rojo  "qmldir no declara Idioma como singleton"
fi

# La pantalla de bloqueo es otro programa: si no usa el singleton, se queda en
# español justo delante de quien todavía no ha entrado.
if grep -q 'Idioma\.t(' build/desktop/quickshell/bloqueo.qml; then
    verde "la pantalla de bloqueo también se traduce"
else
    rojo  "bloqueo.qml no usa el diccionario"
fi

# Un método QML no puede empezar por mayúscula.
#
# Esta comprobación existe porque la primera versión de todo esto llamaba a la
# función de traducir "T()", igual que en C. QML reserva la mayúscula inicial
# para los nombres de tipo, así que eso no es un aviso: es un error de carga
# ("Method names cannot begin with an upper case letter"). Y como el
# diccionario es un singleton declarado en qmldir, el error no se quedaba en su
# archivo: invalidaba el módulo entero, TODOS los componentes de la carpeta
# dejaban de existir y el escritorio no arrancaba.
#
# Lo que duele es que las 13 comprobaciones de este archivo pasaban en verde
# con el fallo dentro: el diccionario estaba completo, sólo que nada podía
# leerlo. qmllint tampoco dice nada --- no resuelve los tipos de Quickshell y
# se calla ---, así que la regla se comprueba aquí a mano.
MAYUS="$(grep -rn '^\s*function [A-Z]' build/desktop/quickshell/*.qml || true)"
if [ -z "$MAYUS" ]; then
    verde "ningún método QML empieza por mayúscula"
else
    rojo  "métodos QML con mayúscula inicial (el escritorio no arrancará):"
    printf '      %s\n' "$MAYUS"
fi

# Los nombres que viven en un array y se pintan con "Idioma.t(modelData.nombre)".
#
# El envoltorio automático sólo ve literales en la misma línea que el "text:",
# así que estos se le escapan enteros: el literal está en la declaración del
# array, veinte pantallas más arriba. Con el menú del Centro de Control ---
# Vistazo, Sistema, Energía, Controladores... --- pasó exactamente eso: las
# quince comprobaciones de este archivo salían en verde y el menú lateral
# estaba entero en español en la versión inglesa.
FALTAN="$(python3 - <<'PY'
import io, re
dic = io.open("build/desktop/quickshell/Idioma.qml", encoding="utf-8").read()
cuerpo = dic[dic.index("property var traducciones"):dic.index("function t(")]
claves = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)":', cuerpo, re.M))
s = io.open("build/desktop/quickshell/shell.qml", encoding="utf-8").read()
# Sólo los arrays cuyos nombres llegan a pintarse: llevan "id:" al lado.
for m in re.finditer(r'\{[^{}]*\bid:\s*"[^"]*"[^{}]*\}', s):
    n = re.search(r'\bnombre:\s*"((?:[^"\\]|\\.)*)"', m.group(0))
    if n and n.group(1) not in claves:
        print(n.group(1))
PY
)"
if [ -z "$FALTAN" ]; then
    verde "los nombres de los menús están en el diccionario"
else
    rojo  "nombres de menú sin traducir:"
    printf '      %s\n' "$FALTAN"
fi

# --------------------------------------------------------------------------
titulo "Pantalla de bienvenida (C)"

FALTAN="$(python3 - <<'PY'
import io, re
s = io.open("build/desktop/settings/m-welcome.c", encoding="utf-8").read()
tabla = s[s.index("static const Trad TRADUCCIONES[]"):s.index("static gboolean en_ingles")]
claves = set(re.findall(r'\{\s*"((?:[^"\\]|\\.)*)"', tabla))
malos = []

# 1. Lo que se envuelve a mano con T("...").
cuerpo = s[s.index("static gboolean en_ingles"):]
def literal_completo(txt, pos):
    """Junta los trozos adyacentes: en C, "a" "b" es una sola cadena."""
    partes, i = [], pos
    while True:
        while i < len(txt) and txt[i] in ' \t\n': i += 1
        if i >= len(txt) or txt[i] != '"': break
        i += 1; buf = ""
        while i < len(txt):
            if txt[i] == '\\': buf += txt[i:i+2]; i += 2; continue
            if txt[i] == '"': i += 1; break
            buf += txt[i]; i += 1
        partes.append(buf)
    return "".join(partes)

for m in re.finditer(r'\bT\(', cuerpo):
    t = literal_completo(cuerpo, m.end())
    if t and t not in claves: malos.append("T(): " + t)

# 2. Las tablas de atajos, que se traducen donde se pintan y no donde se
#    declaran --- así que un atajo nuevo no lleva ningún T() que delate que
#    falta su traducción. Es justo el caso que esta prueba tiene que coger.
for tabla_nombre in ("TERMINAL", "APPS", "WINDOWS", "WORKSPACES", "SYSTEM",
                     "ESENCIALES"):
    m = re.search(r'static const Bind %s\[\]\s*=\s*\{(.*?)\n\};' % tabla_nombre,
                  s, re.S)
    if not m: malos.append("tabla no encontrada: " + tabla_nombre); continue
    for k, d in re.findall(r'\{\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\}',
                           m.group(1)):
        for t in (k, d):
            # Las teclas sin palabras (SUPER + Q) no se traducen.
            if not re.search(r'[a-záéíóúñ]{3}', t): continue
            if t not in claves: malos.append("%s: %s" % (tabla_nombre, t))

# 3. Los títulos de los apartados.
for t in re.findall(r'\{\s*"([^"]+)",\s+[A-Z]+,\s+G_N_ELEMENTS', s):
    if t not in claves: malos.append("apartado: " + t)
for m in sorted(set(malos)): print(m)
PY
)"
if [ -z "$FALTAN" ]; then
    verde "todo lo que se pinta está en el diccionario"
else
    rojo  "hay texto que se pinta y no está traducido:"
    printf '      %s\n' "$FALTAN"
fi

if gcc -fsyntax-only -Wall $(pkg-config --cflags gtk+-3.0) \
       build/desktop/settings/m-welcome.c 2>/dev/null; then
    verde "m-welcome.c compila"
else
    rojo  "m-welcome.c no compila"
fi

# --------------------------------------------------------------------------
titulo "Informe de hardware (m-drivers)"

FALTAN="$(python3 - <<'PY'
import io, re
s = io.open("build/mcore/m-drivers", encoding="utf-8").read()
fn = s[s.index("t() {  # t <plantilla"):s.index('    printf "$_p" "$@"')]
claves = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\)\s*_p=', fn, re.M))
cuerpo = s[s.index('    printf "$_p" "$@"'):]
usadas = set(re.findall(r"\$\(t '([^']*)'", cuerpo))
usadas |= set(re.findall(r"(?:^|[;&|]\s*|\|\| )t '([^']*)'", cuerpo, re.M))
# Las de una sola palabra se llaman sin comillas: $(t Gráfica)
usadas |= set(re.findall(r"\$\(t ([A-ZÁÉÍÓÚÑ][A-Za-zÁÉÍÓÚÑáéíóúñ]+)\)", cuerpo))
for t in sorted(usadas - claves): print(t)
PY
)"
if [ -z "$FALTAN" ]; then
    verde "todas las plantillas usadas tienen traducción"
else
    rojo  "plantillas sin traducir:"
    printf '      %s\n' "$FALTAN"
fi

# Y que de verdad salga en inglés, que es distinto de que el diccionario esté
# completo: una plantilla mal escrita (%s de más) rompe printf sin avisar.
SAL_ES="$(PATH="$RAIZ/build/mcore:$PATH" MIKEOS_LANG=es sh build/mcore/m-drivers 2>/dev/null | head -1)"
SAL_EN="$(PATH="$RAIZ/build/mcore:$PATH" MIKEOS_LANG=en sh build/mcore/m-drivers 2>/dev/null | head -1)"
if [ "$SAL_ES" = "Hardware detectado" ] && [ "$SAL_EN" = "Hardware detected" ]; then
    verde "el informe sale en los dos idiomas"
else
    rojo  "el informe no cambia de idioma (es='$SAL_ES' en='$SAL_EN')"
fi

# El estado es un identificador, no texto: m-welcome.c y el Centro de Control
# comparan contra "ok"/"ausente"/"sin-driver" para decidir qué icono pintar.
# Si algún día se traduce, los dos dejan de funcionar sin un solo error.
# La salida se recoge antes de filtrarla: con "| grep -q", grep cierra la
# tubería en cuanto encuentra la primera línea, m-drivers muere con SIGPIPE y
# "set -o pipefail" convierte eso en un fallo de la comprobación --- que es
# exactamente lo que pasó la primera vez que se ejecutó esto.
BREVE="$(PATH="$RAIZ/build/mcore:$PATH" MIKEOS_LANG=en sh build/mcore/m-drivers --breve 2>/dev/null)"
if printf '%s\n' "$BREVE" \
   | grep -q '^COMP|[^|]*|[^|]*|\(ok\|sin-driver\|sin-firmware\|apagado\|ausente\|mejorable\)|'; then
    verde "los estados siguen sin traducirse (los leen otros programas)"
else
    rojo  "los estados de --breve han cambiado de forma"
fi

# --------------------------------------------------------------------------
titulo "Órdenes de IPC de Quickshell"

# "quickshell ipc call ..." a secas busca una configuración llamada "default"
# en <XDG_CONFIG_HOME>/quickshell/shell.qml. La de MIKE OS está en
# ~/.config/mike/quickshell/shell.qml y la sesión NO exporta XDG_CONFIG_HOME,
# así que toda llamada sin selector falla con "Could not find default config
# directory" --- por la salida de error de un proceso en segundo plano, o sea
# a ningún sitio.
#
# Así estaban SUPER+W (fondos de pantalla) y los dos botones de la pantalla de
# bienvenida que abren el Centro de Control: sin hacer nada al pulsarlos, sin
# un mensaje, desde que se escribieron. Un botón que no hace nada es peor que
# no tener el botón.
# Se mira en python y no con grep porque hay que saltarse los COMENTARIOS que
# citan la orden mala para explicar por qué es mala --- incluido el de este
# mismo archivo. Un grep que se encuentra a sí mismo es una prueba que nunca
# pasa.
SIN_RUTA="$(python3 - <<'PY'
import os, io
malas = []
for base in ("build/desktop", "scripts", "tests"):
    for dp, _, fs in os.walk(base):
        for f in fs:
            p = os.path.join(dp, f)
            if p == "tests/traducciones.sh":
                continue
            try:
                lineas = io.open(p, encoding="utf-8").read().split("\n")
            except Exception:
                continue
            for i, l in enumerate(lineas, 1):
                if "quickshell ipc call" not in l:
                    continue
                desnuda = l.strip()
                if desnuda.startswith(("#", "//", "*", "/*")):
                    continue
                malas.append("%s:%d" % (p, i))
for m in malas:
    print(m)
PY
)"
if [ -z "$SIN_RUTA" ]; then
    verde "todas llevan --path, --id o --pid"
else
    rojo  "llamadas de IPC sin selector (no harán nada):"
    printf '      %s\n' "$SIN_RUTA"
fi

# --------------------------------------------------------------------------
titulo "El instalador cumple lo que promete"

if grep -q '"--idioma", idioma' build/desktop/quickshell/instalador.qml; then
    verde "el instalador pasa el idioma elegido a m-install"
else
    rojo  "el instalador no pasa el idioma: la elección se pierde al instalar"
fi

if grep -q -- '--idioma)' build/mcore/m-install \
&& grep -q 'etc/mikeos/idioma' build/mcore/m-install; then
    verde "m-install lo guarda en el sistema nuevo"
else
    rojo  "m-install no guarda el idioma"
fi

if grep -q 'Idioma\.cambiar(' build/desktop/quickshell/shell.qml; then
    verde "el Centro de Control deja cambiarlo, como dice el instalador"
else
    rojo  "no hay dónde cambiar el idioma en el Centro de Control"
fi

# --------------------------------------------------------------------------
printf '\n\033[1m%d de %d\033[0m\n' "$OK" "$((OK+MAL))"
[ "$MAL" -eq 0 ]
