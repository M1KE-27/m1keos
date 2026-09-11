#!/bin/bash
# ==============================================================================
# generar-web.sh - construye m1keos.duckdns.org desde el propio repositorio.
#
# La documentación se genera desde docs/, no se copia a mano: una web con la
# documentación pegada a mano se queda vieja el primer día que alguien toca un
# archivo y no se acuerda de actualizar las dos copias.
#
# Igual las cifras (tamaño de la ISO, versión del kernel, número de paquetes):
# salen de los archivos de verdad en cada ejecución.
#
#   ./scripts/generar-web.sh            genera build/web/
#   ./scripts/generar-web.sh --subir    genera y sube al mini PC
# ==============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB="$RAIZ/build/web"
# El servidor no va escrito aquí: esto es un repositorio público y la dirección
# del equipo de casa de cada uno no pinta nada en él. Se pone en
# .publicar.conf (que no se versiona) o en la variable MIKEOS_SERVIDOR.
[ -f "$RAIZ/.publicar.conf" ] && . "$RAIZ/.publicar.conf"
SERVIDOR="${MIKEOS_SERVIDOR:-}"
if [ -z "$SERVIDOR" ]; then
    err "no sé a qué servidor subir."
    gris "  Crea $RAIZ/.publicar.conf con:"
    gris "      MIKEOS_SERVIDOR=usuario@tu-servidor"
    gris "  o exporta MIKEOS_SERVIDOR antes de ejecutar esto."
    exit 1
fi
DESTINO="${MIKEOS_WEB_DIR:-/home/m1ke/mikeos-backend/web}"

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }

SUBIR=0
[ "${1:-}" = "--subir" ] && SUBIR=1

mkdir -p "$WEB" "$WEB/docs" "$WEB/wiki" "$WEB/capturas" "$WEB/descargas"

# --- Datos reales, leídos de los archivos ------------------------------------
paso "Leyendo los datos del sistema"
ISO="$RAIZ/iso/mikeos.iso"
KVER="$(cat "$RAIZ/kernel/include/config/kernel.release" 2>/dev/null || echo "desconocida")"
if [ -f "$ISO" ]; then
    ISO_TAM="$(du -h "$ISO" | cut -f1)"
    ISO_SHA="$(cut -d' ' -f1 "$ISO.sha256" 2>/dev/null || sha256sum "$ISO" | cut -d' ' -f1)"
    HAY_ISO=1
else
    HAY_ISO=0; ISO_TAM="—"; ISO_SHA="—"
fi
N_PKG="$(find "$RAIZ/build/repo" -name '*.mpk' 2>/dev/null | wc -l | tr -d ' ')"
FECHA="$(date +'%-d de %B de %Y')"
gris "  kernel $KVER · ISO $ISO_TAM · $N_PKG paquetes"

# --- Hoja de estilo compartida ------------------------------------------------
# Los mismos cinco colores que el escritorio (ver quickshell/Paleta.qml): la web
# y el sistema tienen que parecer la misma cosa.
cat > "$WEB/estilo.css" <<'CSS'
:root{
  --fondo:#0b0d11; --superficie:#161a21; --superficie-alta:#1f242d;
  --borde:#262c36; --texto:#e8ebf0; --tenue:#79818f; --acento:#00d4ff;
}
*{box-sizing:border-box}
body{margin:0;background:var(--fondo);color:var(--texto);
  font:15px/1.65 system-ui,-apple-system,"Segoe UI",sans-serif;
  -webkit-font-smoothing:antialiased}
.cont{max-width:900px;margin:0 auto;padding:0 24px}
a{color:var(--acento);text-decoration:none}
a:hover{text-decoration:underline}
nav{border-bottom:1px solid var(--borde);position:sticky;top:0;
  background:rgba(11,13,17,.92);backdrop-filter:blur(8px);z-index:10}
nav .cont{display:flex;align-items:center;gap:24px;height:56px}
nav .marca{display:flex;align-items:center;gap:10px;font-weight:700;
  color:var(--texto);margin-right:auto}
nav .marca svg{width:20px;height:20px}
nav a.enl{color:var(--tenue);font-size:14px}
nav a.enl:hover{color:var(--texto);text-decoration:none}
nav a.enl.aqui{color:var(--texto)}
header{padding:64px 0 40px}
h1{font-size:clamp(30px,5.5vw,46px);margin:0 0 14px;letter-spacing:-1px;line-height:1.12}
h2{font-size:13px;text-transform:uppercase;letter-spacing:1.2px;
  color:var(--tenue);margin:44px 0 18px;font-weight:700}
h3{font-size:16px;margin:28px 0 8px}
.lema{color:var(--tenue);font-size:18px;max-width:52ch;margin:0}
.estado{display:inline-block;border:1px solid var(--borde);border-radius:999px;
  padding:4px 12px;font-size:12px;color:var(--tenue);margin-bottom:18px}
.punto{display:inline-block;width:6px;height:6px;border-radius:50%;
  background:var(--acento);margin-right:7px;vertical-align:1px}
.cifras{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));
  gap:1px;background:var(--borde);border:1px solid var(--borde);
  border-radius:10px;overflow:hidden;margin:36px 0}
.cifra{background:var(--superficie);padding:18px}
.cifra b{display:block;font-size:22px;color:var(--acento);font-weight:700}
.cifra span{color:var(--tenue);font-size:12px}
pre{background:var(--superficie);border:1px solid var(--borde);border-radius:8px;
  padding:15px 17px;overflow-x:auto;margin:14px 0;
  font:13px/1.7 ui-monospace,"SF Mono",Menlo,monospace}
pre .c{color:var(--tenue)}
code{background:var(--superficie);border:1px solid var(--borde);border-radius:4px;
  padding:1px 5px;font:13px ui-monospace,Menlo,monospace}
pre code{background:none;border:none;padding:0}
.rejilla{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px}
.tarj{background:var(--superficie);border:1px solid var(--borde);
  border-radius:10px;padding:18px}
.tarj h3{margin:0 0 6px;font-size:15px}
.tarj p{margin:0;color:var(--tenue);font-size:14px}
.boton{display:inline-block;background:var(--acento);color:#05070c;
  font-weight:700;padding:11px 22px;border-radius:8px;font-size:15px}
.boton:hover{background:#33ddff;text-decoration:none}
.boton.sec{background:var(--superficie-alta);color:var(--texto);
  border:1px solid var(--borde)}
.tenue{color:var(--tenue)}
figure{margin:22px 0}
figure img{width:100%;border:1px solid var(--borde);border-radius:10px;display:block}
figcaption{color:var(--tenue);font-size:13px;margin-top:8px}
table{width:100%;border-collapse:collapse;margin:16px 0;font-size:14px}
th,td{text-align:left;padding:9px 12px;border-bottom:1px solid var(--borde)}
th{color:var(--tenue);font-size:12px;text-transform:uppercase;letter-spacing:.6px}
.aviso{background:var(--superficie);border:1px solid var(--borde);
  border-left:3px solid var(--acento);border-radius:6px;padding:14px 16px;margin:18px 0}
.aviso p{margin:0;font-size:14px}
footer{padding:40px 0 64px;margin-top:56px;border-top:1px solid var(--borde);
  color:var(--tenue);font-size:13px}
ul,ol{padding-left:22px}
li{margin:5px 0}
li > ul,li > ol{margin:5px 0}
/* Dentro de un documento, los encabezados son jerarquía real, no etiquetas de
   sección: h2 en mayúsculas pequeñas se come la estructura de un texto largo. */
article h2{font-size:22px;text-transform:none;letter-spacing:-.3px;
  color:var(--texto);margin:40px 0 12px;font-weight:700}
article h3{font-size:17px;margin:26px 0 8px}
article h4{font-size:15px;margin:22px 0 6px;color:var(--tenue)}
blockquote{margin:16px 0;padding:2px 0 2px 16px;border-left:3px solid var(--borde);
  color:var(--tenue)}
blockquote p{margin:6px 0}
hr{border:none;border-top:1px solid var(--borde);margin:32px 0}
table code{font-size:12px}
td strong{color:var(--texto)}
/* Una tabla ancha desborda el móvil; que se desplace ella, no la página. */
.tabla-ancha{overflow-x:auto}
CSS

# --- Cabecera y pie compartidos ----------------------------------------------
cabecera() {  # cabecera <titulo> <seccion-activa> <prefijo-de-ruta>
    local t="$1" act="$2" pre="$3"
    cat <<HTML
<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$t</title><link rel="stylesheet" href="${pre}estilo.css"></head><body>
<nav><div class="cont">
  <a class="marca" href="${pre}index.html">
    <svg viewBox="0 0 24 24" fill="none" stroke="#e8ebf0" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round"><path d="M5 6l6 6-6 6"/><path d="M13 18h7"/></svg>
    MIKE OS</a>
  <a class="enl $([ "$act" = inicio ] && echo aqui)" href="${pre}index.html">Inicio</a>
  <a class="enl $([ "$act" = descargas ] && echo aqui)" href="${pre}descargas.html">Descargar</a>
  <a class="enl $([ "$act" = docs ] && echo aqui)" href="${pre}docs/index.html">Documentación</a>
  <a class="enl $([ "$act" = wiki ] && echo aqui)" href="${pre}wiki/index.html">Wiki</a>
</div></nav>
<div class="cont">
HTML
}
pie() {
    cat <<HTML
<footer>MIKE OS · servido desde un mini PC en casa · actualizado el $FECHA</footer>
</div></body></html>
HTML
}

# --- Página de inicio ---------------------------------------------------------
paso "Página de inicio"
{
cabecera "MIKE OS" inicio ""
cat <<HTML
<header>
  <div class="estado"><span class="punto"></span>En desarrollo · arranca en hardware UEFI</div>
  <h1>Un sistema operativo hecho desde cero.</h1>
  <p class="lema">Kernel Linux propio, init con runit, gestor de paquetes propio
    y escritorio propio. Cero systemd.</p>
</header>

<div class="cifras">
  <div class="cifra"><b>0,59 s</b><span>en arrancar</span></div>
  <div class="cifra"><b>50 MB</b><span>de RAM en reposo</span></div>
  <div class="cifra"><b>0 %</b><span>systemd</span></div>
  <div class="cifra"><b>$ISO_TAM</b><span>la imagen entera</span></div>
</div>

<figure>
  <img src="capturas/escritorio.png" alt="El escritorio de MIKE OS">
  <figcaption>El escritorio: Hyprland con la barra de MIKE OS.</figcaption>
</figure>

<h2>Sin gestor de arranque</h2>
<p>El kernel se compila con <code>CONFIG_EFI_STUB</code>, así que es él mismo un
  ejecutable UEFI: se copia en la partición EFI como
  <code>EFI/BOOT/BOOTX64.EFI</code> y la firmware lo arranca directamente. No hay
  GRUB que mantener ni que se pueda romper.</p>

<h2>Qué lleva dentro</h2>
<div class="rejilla">
  <div class="tarj"><h3>Kernel $KVER</h3>
    <p>Compilado para este sistema. Soporte de hardware real, arranque UEFI y
      la configuración afinada para portátil.</p></div>
  <div class="tarj"><h3>mpm</h3>
    <p>Gestor de paquetes propio: verificación SHA256, resolución de
      dependencias e instantáneas de btrfs antes de instalar.</p></div>
  <div class="tarj"><h3>Escritorio</h3>
    <p>Barra y Centro de Control escritos para MIKE OS. Se configura todo sin
      tocar un archivo.</p></div>
  <div class="tarj"><h3>MKShell</h3>
    <p>Shell propia en C, con tuberías, redirecciones y variables.</p></div>
</div>

<h2>Actualizaciones</h2>
<p>Las actualizaciones se piden, no se empujan. El repositorio ya viene
  configurado, así que basta con:</p>
<pre><span class="c"># cuando quieras la última versión</span>
mpm update &amp;&amp; mpm upgrade</pre>
<p class="tenue">El kernel también viaja por ahí, y al instalarse conserva el
  anterior para poder volver si no arranca.
  <a href="docs/actualizaciones.html">Cómo funciona →</a></p>

<p style="margin-top:36px">
  <a class="boton" href="descargas.html">Descargar</a>
  <a class="boton sec" href="docs/index.html" style="margin-left:8px">Documentación</a>
</p>
HTML
pie
} > "$WEB/index.html"

# --- Descargas ----------------------------------------------------------------
paso "Descargas"
{
cabecera "Descargar · MIKE OS" descargas ""
if [ "$HAY_ISO" -eq 1 ]; then
cat <<HTML
<header><h1>Descargar</h1>
<p class="lema">Una imagen que arranca en cualquier equipo con UEFI. Puedes
  probar el sistema sin instalar nada.</p></header>

<table>
  <tr><th>Archivo</th><th>Tamaño</th><th>Kernel</th></tr>
  <tr><td><a href="descargas/mikeos.iso">mikeos.iso</a></td><td>$ISO_TAM</td><td>$KVER</td></tr>
</table>
<p class="tenue">SHA256:<br><code style="font-size:11px;word-break:break-all">$ISO_SHA</code></p>
<p><a class="boton" href="descargas/mikeos.iso">Descargar la imagen</a></p>

<h2>Grabarla en un USB</h2>
<pre><span class="c"># comprueba antes que lo descargado es lo que se publicó</span>
sha256sum mikeos.iso

<span class="c"># /dev/sdX es tu USB. Se borrará entero.</span>
sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync</pre>

<div class="aviso"><p><strong>Secure Boot.</strong> Hay que desactivarlo en la
  UEFI antes de arrancar el USB. Este kernel no lleva la firma de Microsoft, así
  que con Secure Boot activado la firmware se niega a ejecutarlo. En una Surface
  se desactiva entrando en la UEFI (mantén subir volumen mientras enciendes).</p></div>

<h2>Probar sin instalar</h2>
<p>La imagen arranca en memoria: puedes mirarla, tocarlo todo y apagar sin que
  el disco se entere. Cuando quieras instalarla, abre una terminal con
  <code>SUPER/ALT + Return</code> y escribe <code>m-install</code>.</p>
<p><a href="docs/instalacion.html">Guía de instalación completa →</a></p>
HTML
else
cat <<HTML
<header><h1>Descargar</h1></header>
<div class="aviso"><p>Todavía no hay ninguna imagen publicada.</p></div>
HTML
fi
pie
} > "$WEB/descargas.html"

verde "  index.html y descargas.html"

# --- Documentación, generada desde docs/ --------------------------------------
# El contenido vive en el repositorio y aquí sólo se convierte. Copiarlo a mano
# significaría dos verdades distintas en cuanto alguien tocara una.
paso "Documentación"
python3 - "$RAIZ" "$WEB" <<'PYEOF'
import os, re, sys
raiz, web = sys.argv[1], sys.argv[2]
docs = os.path.join(raiz, "docs")

def md_a_html(texto):
    """Markdown de verdad, con python-markdown.

    Aquí había un conversor escrito a mano de cuarenta líneas. Cubría lo que
    usaban los documentos ese día y nada más: las listas anidadas se aplanaban,
    el texto dentro de las celdas de una tabla no se formateaba, los bloques de
    cita desaparecían y cualquier cosa que no estuviera prevista salía como
    texto suelto. Y fallaba en silencio, que es lo peor: la página se generaba
    igual, sólo que mal.

    Las extensiones son las que usan los documentos del proyecto:
      tables      las comparativas y el registro del plan
      fenced_code los bloques con ```
      sane_lists  listas anidadas que no se mezclan entre sí
      attr_list   poder poner clases en un elemento suelto
      toc         índices dentro de un documento
      nl2br       NO se usa: los saltos sueltos son del ancho del archivo,
                  no párrafos nuevos
    """
    import markdown
    html_generado = markdown.markdown(
        texto,
        extensions=["tables", "fenced_code", "sane_lists", "attr_list", "toc"],
        output_format="html",
    )
    # Una tabla de atajos con dos columnas anchas desborda el móvil. Que se
    # desplace la tabla, no la página entera: una página que se mueve de lado
    # se siente rota.
    html_generado = html_generado.replace(
        "<table>", '<div class="tabla-ancha"><table>').replace(
        "</table>", "</table></div>")
    return html_generado


TITULOS = {
    "architecture": "Arquitectura", "boot": "Arranque", "kernel": "Kernel",
    "mcore": "Herramientas mcore", "mkshell": "MKShell", "mpm": "Gestor de paquetes",
    "networking": "Red", "recovery": "Modo rescate", "runit": "Init con runit",
    "ssh": "SSH", "desktop": "Escritorio", "development": "Desarrollo",
    "benchmarks": "Rendimiento",
}

def pagina(titulo, cuerpo, activa="docs", pre="../"):
    return f'''<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{titulo} · MIKE OS</title><link rel="stylesheet" href="{pre}estilo.css"></head><body>
<nav><div class="cont">
  <a class="marca" href="{pre}index.html">
    <svg viewBox="0 0 24 24" fill="none" stroke="#e8ebf0" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round"><path d="M5 6l6 6-6 6"/><path d="M13 18h7"/></svg>
    MIKE OS</a>
  <a class="enl" href="{pre}index.html">Inicio</a>
  <a class="enl" href="{pre}descargas.html">Descargar</a>
  <a class="enl {'aqui' if activa=='docs' else ''}" href="{pre}docs/index.html">Documentación</a>
  <a class="enl {'aqui' if activa=='wiki' else ''}" href="{pre}wiki/index.html">Wiki</a>
</div></nav>
<div class="cont">
{cuerpo}
<footer>MIKE OS · <a href="{pre}index.html">Inicio</a></footer>
</div></body></html>'''

generadas = []
if os.path.isdir(docs):
    for archivo in sorted(os.listdir(docs)):
        if not archivo.endswith(".md"):
            continue
        base = archivo[:-3]
        if base.startswith("plan-"):      # el plan es de trabajo, no de usuario
            continue
        titulo = TITULOS.get(base, base.replace("-", " ").capitalize())
        cuerpo = md_a_html(open(os.path.join(docs, archivo)).read())
        open(os.path.join(web, "docs", base + ".html"), "w").write(
            pagina(titulo,
                   f"<header><h1>{titulo}</h1></header>\n<article>{cuerpo}</article>"))
        generadas.append((base, titulo))

enlaces = "\n".join(
    f'<div class="tarj"><h3><a href="{b}.html">{t}</a></h3></div>' for b, t in generadas)
indice = f'''<header><h1>Documentación</h1>
<p class="lema">Cómo está hecho MIKE OS por dentro. Se genera desde el propio
repositorio, así que no puede quedarse vieja.</p></header>
<h2>Empezar</h2>
<div class="rejilla">
  <div class="tarj"><h3><a href="instalacion.html">Instalación</a></h3>
    <p>Del USB al primer arranque.</p></div>
  <div class="tarj"><h3><a href="actualizaciones.html">Actualizaciones</a></h3>
    <p>Cómo llega a tu equipo lo que cambia.</p></div>
</div>
<h2>El sistema por dentro</h2>
<div class="rejilla">
{enlaces}
</div>'''
open(os.path.join(web, "docs", "index.html"), "w").write(pagina("Documentación", indice))
print(f"  {len(generadas)} documentos generados desde docs/")
PYEOF

verde "  documentación"

# --- Dos guías escritas a mano -----------------------------------------------
# Estas no salen de docs/ porque no existen ahí: son para quien usa el sistema,
# no para quien lo construye.
paso "Guías de instalación y actualizaciones"
guia() {  # guia <archivo> <titulo> ; el cuerpo llega por la entrada estándar
    { cabecera "$2 · MIKE OS" docs "../"; cat; pie; } > "$WEB/docs/$1"
}

guia instalacion.html "Instalación" <<HTML
<header><h1>Instalación</h1>
<p class="lema">Del USB al primer arranque.</p></header>

<h2>1. Grabar el USB</h2>
<pre><span class="c"># /dev/sdX es tu USB. Se borra entero: comprueba cuál es.</span>
lsblk
sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync</pre>

<h2>2. Desactivar Secure Boot</h2>
<div class="aviso"><p>Sin esto el USB no arranca. La firmware se niega a
ejecutar un kernel que no lleve la firma de Microsoft, y este no la lleva.</p></div>
<p><strong>En una Surface:</strong> apágala del todo. Mantén pulsado
<strong>subir volumen</strong> y pulsa el botón de encendido; suelta el volumen
cuando aparezca el logo. En <em>Security</em> pon Secure Boot en
<em>Disabled</em>. En <em>Boot configuration</em>, sube <em>USB Storage</em> por
encima del disco interno.</p>
<p><strong>En otros equipos:</strong> la tecla suele ser Supr, F2 o F12 nada más
encender.</p>

<h2>3. Probar sin instalar</h2>
<p>MIKE OS arranca en memoria. Puedes mirarlo todo, abrir la terminal, tocar los
ajustes y apagar: el disco no se entera de nada.</p>

<h2>4. Instalar</h2>
<p>Abre una terminal con <code>SUPER/ALT + Return</code> y escribe:</p>
<pre>m-install</pre>
<p>Sin argumentos lista los discos que ve. Después:</p>
<pre>m-install /dev/nvme0n1</pre>
<p>Te preguntará el sistema de archivos, el teclado, la zona horaria y el nombre
del equipo. Y pedirá que escribas <code>BORRAR</code> antes de tocar nada.</p>

<h3>¿btrfs o ext4?</h3>
<table>
  <tr><th></th><th>btrfs</th><th>ext4</th></tr>
  <tr><td>Instantáneas antes de instalar</td><td>sí, y son inmediatas</td><td>no</td></tr>
  <tr><td>Volver atrás de una actualización</td><td>completo</td><td>sólo lo que mpm conoce</td></tr>
  <tr><td>Compresión</td><td>sí</td><td>no</td></tr>
  <tr><td>Sencillez</td><td>más piezas</td><td>máxima</td></tr>
</table>
<p class="tenue">Con btrfs, <code>mpm</code> toma una foto del sistema antes de
tocar nada y <code>mpm rollback</code> vuelve a ella. Por eso es lo que propone
el instalador.</p>

<h2>Qué hace el instalador</h2>
<ul>
  <li>Tabla de particiones GPT.</li>
  <li>Partición EFI de 512 MiB en FAT32.</li>
  <li>Raíz en btrfs con subvolúmenes <code>@</code>, <code>@home</code> y
      <code>@instantaneas</code>, o en ext4.</li>
  <li><code>fstab</code> por UUID, no por <code>/dev/sdX</code>: enchufar un USB
      puede cambiar los nombres entre arranques.</li>
  <li>El kernel en la partición EFI, y registrado en el menú de la UEFI.</li>
</ul>
HTML

guia actualizaciones.html "Actualizaciones" <<HTML
<header><h1>Actualizaciones</h1>
<p class="lema">Se piden, no se empujan.</p></header>

<h2>Ponerte al día</h2>
<pre>mpm update &amp;&amp; mpm upgrade</pre>
<p>El repositorio oficial ya viene configurado en el sistema. Si quieres
comprobarlo o añadir otro:</p>
<pre>mpm source list
mpm source add https://m1keos.duckdns.org/mpm/</pre>

<h2>Qué se actualiza así</h2>
<table>
  <tr><th>Paquete</th><th>Qué lleva</th></tr>
  <tr><td>mpm</td><td>El propio gestor de paquetes</td></tr>
  <tr><td>mcore</td><td>Las herramientas <code>m-*</code> del sistema</td></tr>
  <tr><td>mike-desktop</td><td>La barra, el Centro de Control, Hyprland</td></tr>
  <tr><td>mkshell</td><td>La shell</td></tr>
  <tr><td>mikeos-kernel</td><td>El kernel</td></tr>
</table>

<h2>Si algo sale mal</h2>
<pre>mpm rollback</pre>
<p>En btrfs vuelve a la instantánea que se tomó justo antes de instalar: el
sistema entero, no una lista de archivos.</p>

<h3>Si el kernel nuevo no arranca</h3>
<p>Al instalarse, el kernel anterior se guarda en la partición EFI como
<code>EFI/mikeos/vmlinuz-anterior.efi</code>. Se elige desde el menú de arranque
de la UEFI y el equipo vuelve a encender. Un kernel sin vuelta atrás es un
portátil que no enciende.</p>

<h2>Cosas que conviene saber</h2>
<ul>
  <li><strong>Nada se instala solo.</strong> Actualizar es una decisión tuya.</li>
  <li><strong>Un programa abierto no cambia de versión.</strong> La barra se
      recarga al reiniciar la sesión; el kernel, al reiniciar el equipo. Pasa en
      todos los sistemas.</li>
  <li><strong>Cada paquete se verifica</strong> por SHA256 contra el índice
      antes de instalarse.</li>
</ul>
HTML
verde "  guías"

# --- Wiki ---------------------------------------------------------------------
paso "Wiki"
{
cabecera "Wiki · MIKE OS" wiki "../"
cat <<HTML
<header><h1>Wiki</h1>
<p class="lema">Lo que se aprende usando el sistema: problemas concretos y cómo
se resuelven.</p></header>

<h2>Arranque</h2>
<h3>El USB no arranca</h3>
<p>Casi siempre es Secure Boot. Desactívalo en la UEFI
(<a href="../docs/instalacion.html">cómo</a>). Si sigue sin arrancar, comprueba
que el orden de arranque pone el USB por delante del disco interno.</p>

<h3>Arranca pero la pantalla se queda en negro</h3>
<p>Suele ser firmware de la gráfica que falta. Entra por SSH o con
<code>SUPER + F1</code> y mira <code>dmesg | grep -i firmware</code>. La imagen
base sólo trae el firmware de AMD y Qualcomm; el de Intel y otros se instala
aparte con <code>mpm</code>.</p>

<h2>Hardware</h2>
<h3>No hay sonido</h3>
<p>Comprueba en este orden:</p>
<pre><span class="c"># ¿el kernel ve una tarjeta?</span>
cat /proc/asound/cards

<span class="c"># ¿hay una salida montada?</span>
wpctl status

<span class="c"># ¿qué dice el sistema?</span>
m-volume get</pre>
<p>Si <code>/proc/asound/cards</code> dice «no soundcards», es cosa del kernel,
no del escritorio.</p>

<h3>No hay WiFi</h3>
<p><code>m-wifi list</code> para ver las redes y <code>m-drivers</code> para
saber si falta firmware de tu tarjeta.</p>

<h3>El touchpad no responde en una Surface</h3>
<p>En las Surface, el teclado y el touchpad cuelgan de un microcontrolador de
Microsoft (el Surface Aggregator), no del bus donde uno los buscaría. Si no
responden, mira <code>dmesg | grep -i surface</code>.</p>

<h2>El escritorio</h2>
<h3>La barra ha desaparecido</h3>
<p>Se levanta sola en menos de un segundo. Si no vuelve, desde una terminal:</p>
<pre>pkill quickshell    <span class="c"># m-panel la relanza</span></pre>

<h3>El fondo de pantalla no se guarda</h3>
<p>Debería. <code>m-fondo actual</code> dice cuál está en uso y
<code>m-fondo poner &lt;ruta&gt;</code> lo cambia y lo recuerda.</p>

<h3>Cambiar la barra de sitio, los colores, el reloj</h3>
<p>Todo está en el Centro de Control, en el icono de la derecha de la barra.
Y si prefieres el archivo: <code>~/.config/mike/settings.conf</code>, que lleva
los valores válidos comentados al lado.</p>

<h2>Paquetes</h2>
<h3>Instalar algo que no está</h3>
<pre>mpm search &lt;nombre&gt;
mpm install &lt;nombre&gt;</pre>
<p>Busca en el repositorio de MIKE OS y en core/extra de Arch, que son unos
15.000 paquetes.</p>

<h3>Una instalación va lentísima</h3>
<p>Si estás en una máquina virtual, comprueba que la virtualización por hardware
está activada en la BIOS del anfitrión (<code>SVM Mode</code> en AMD,
<code>VT-x</code> en Intel). Sin ella todo va entre diez y cincuenta veces más
lento.</p>

<h2>Diagnóstico</h2>
<pre>m-doctor            <span class="c"># revisión general</span>
m-info              <span class="c"># qué es este equipo</span>
m-service           <span class="c"># servicios en marcha</span>
m-log               <span class="c"># registro del sistema</span></pre>
HTML
pie
} > "$WEB/wiki/index.html"
verde "  wiki"

# --- Capturas -----------------------------------------------------------------
paso "Galería"
{
cabecera "Capturas · MIKE OS" inicio "../"
echo '<header><h1>Capturas</h1><p class="lema">Sacadas del sistema recién construido, no de un montaje.</p></header>'
for par in "escritorio:El escritorio, con la barra de MIKE OS" \
           "bienvenida:La pantalla de inicio, la primera vez" \
           "centro-de-control:El Centro de Control" \
           "ajustes-escritorio:Ajustes del escritorio" \
           "terminal:La terminal"; do
    n="${par%%:*}"; d="${par#*:}"
    [ -f "$WEB/capturas/$n.png" ] || continue
    printf '<figure><img src="%s.png" alt="%s"><figcaption>%s</figcaption></figure>\n' "$n" "$d" "$d"
done
pie
} > "$WEB/capturas/index.html"
verde "  galería"

# --- La ISO -------------------------------------------------------------------
if [ "$HAY_ISO" -eq 1 ]; then
    paso "Copiando la imagen"
    cp "$ISO" "$WEB/descargas/mikeos.iso"
    [ -f "$ISO.sha256" ] && cp "$ISO.sha256" "$WEB/descargas/mikeos.iso.sha256"
    verde "  mikeos.iso ($ISO_TAM)"
fi

echo
verde "Web generada en $WEB"

# --- Subir --------------------------------------------------------------------
if [ "$SUBIR" -eq 1 ]; then
    echo
    paso "Subiendo a $SERVIDOR"
    # --exclude mpm/: el repositorio de paquetes lo gestiona publicar.sh y vive
    # en la misma carpeta; sincronizar con --delete se lo llevaría por delante.
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete --exclude 'mpm/' --info=stats1 "$WEB/" "$SERVIDOR:$DESTINO/" || exit 1
    else
        tar -C "$WEB" -czf - . | ssh "$SERVIDOR" "tar -C '$DESTINO' -xzf -" || exit 1
    fi
    verde "  subido"
    paso "Comprobando"
    for ruta in "" "descargas.html" "docs/index.html" "wiki/index.html" "capturas/index.html"; do
        cod="$(curl -fsS --max-time 15 -o /dev/null -w '%{http_code}' "https://m1keos.duckdns.org/$ruta" 2>/dev/null || echo ---)"
        printf '    %-24s %s\n' "/$ruta" "$cod"
    done
fi
