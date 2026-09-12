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
DESTINO="${MIKEOS_WEB_DIR:-/home/m1ke/mikeos-backend/web}"

verde() { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
paso()  { printf '\033[1m»\033[0m %s\n' "$*"; }
err()   { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

# Sólo hace falta un servidor si de verdad se va a subir algo. Construir en
# local no necesita ninguno, y exigirlo hacía que este script fallara en
# cualquier clon recién bajado (lo cazó la integración continua en su primera
# ejecución). Además la comprobación estaba ANTES de definir err(), así que ni
# siquiera sabía explicarse.
exigir_servidor() {
    [ -n "$SERVIDOR" ] && return 0
    err "no sé a qué servidor subir."
    gris "  Crea $RAIZ/.publicar.conf con:"
    gris "      MIKEOS_SERVIDOR=usuario@tu-servidor"
    gris "  o exporta MIKEOS_SERVIDOR antes de ejecutar esto."
    exit 1
}


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
# La ISO se sirve desde las releases de GitHub, no desde aquí. La etiqueta sale
# de la última publicada, así que la web no puede quedarse enlazando una vieja.
ETIQUETA_ISO="$(gh release list --repo "${MIKEOS_REPO_GITHUB:-M1KE-27/m1keos}" --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)"
# La versión sale del archivo VERSION de la raíz, que es la única fuente: la
# misma que acaba en /etc/os-release y en el Centro de Control.
VERSION="$(tr -d ' \n' < "$RAIZ/VERSION" 2>/dev/null || echo 0.0.0)"
[ -n "$ETIQUETA_ISO" ] || ETIQUETA_ISO="v$VERSION"
URL_ISO="https://github.com/${MIKEOS_REPO_GITHUB:-M1KE-27/m1keos}/releases/download/$ETIQUETA_ISO/mikeos.iso"
FECHA="$(date +'%-d de %B de %Y')"
gris "  kernel $KVER · ISO $ISO_TAM · $N_PKG paquetes"

# --- Hoja de estilo compartida ------------------------------------------------
#
# Los colores son los del escritorio (build/desktop/quickshell/Paleta.qml). Para
# el sitio de un sistema operativo, la fuente honesta de color es el propio
# sistema: lo que se ve aquí es lo que se ve al arrancarlo.
#
# La regla que lo separa del "dark tech" de plantilla es la misma que sigue el
# escritorio: el acento SÓLO para lo que está vivo. En toda la página aparece en
# cinco sitios contados. El color lo ponen las capturas, no la decoración.
#
# Y una idea tipográfica, una sola: la letra dice quién escribió la cadena. Lo
# que escribió una persona va en Geist; lo que escribió una máquina (órdenes,
# rutas, tamaños, sumas de verificación, líneas de registro) va en mono. Nunca
# mono para etiquetas ni para adornar.
paso "Escribiendo la hoja de estilo"
cat > "$WEB/estilo.css" <<'CSS'
/* Autoalojadas: 60 KB que sirve el mismo mini PC. Enlazar Google Fonts sería
   mandar a cada visitante a pedirle algo a un tercero sin necesidad. */
@font-face{font-family:Geist;src:url(tipos/geist-400.woff2)format("woff2");font-weight:400;font-display:swap}
@font-face{font-family:Geist;src:url(tipos/geist-500.woff2)format("woff2");font-weight:500;font-display:swap}
@font-face{font-family:Geist;src:url(tipos/geist-700.woff2)format("woff2");font-weight:700;font-display:swap}
@font-face{font-family:"JB Mono";src:url(tipos/jbmono-400.woff2)format("woff2");font-weight:400;font-display:swap}

:root{
  --lienzo:#090b10;
  --superficie:#12161d;
  --borde:#232a35;
  --texto:#e8ebf0;
  --tenue:#79818f;
  --vivo:#00d4ff;

  --sans:Geist,ui-sans-serif,system-ui,sans-serif;
  --mono:"JB Mono",ui-monospace,SFMono-Regular,monospace;

  /* Una sola escala de radios, documentada: reglas estructurales a 0,
     superficies e imágenes a 10, cosas pulsables en cápsula. */
  --r-sup:10px;
}

*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{
  margin:0;background:var(--lienzo);color:var(--texto);
  font-family:var(--sans);font-size:17px;line-height:1.65;
  font-weight:400;letter-spacing:-0.003em;
  -webkit-font-smoothing:antialiased;
}
::selection{background:var(--vivo);color:#04121a}

.cont{max-width:1180px;margin:0 auto;padding:0 32px}
.prosa{max-width:68ch}

/* --- Navegación. Una línea, 64 px, sin excepciones. --- */
nav{border-bottom:1px solid var(--borde);position:sticky;top:0;z-index:10;
    background:rgba(9,11,16,.86);backdrop-filter:blur(14px)}
nav .cont{display:flex;align-items:center;gap:28px;height:64px}
.marca{display:flex;align-items:center;gap:9px;color:var(--texto);
       text-decoration:none;font-weight:700;letter-spacing:-0.02em;margin-right:8px}
.marca svg{width:17px;height:17px;flex:none}
.enl{color:var(--tenue);text-decoration:none;font-size:14.5px;font-weight:500}
.enl:hover{color:var(--texto)}
.enl.aqui{color:var(--texto)}
nav .derecha{margin-left:auto}

/* --- Botones. Cápsula, y sólo el primario lleva el acento. --- */
.btn{display:inline-block;padding:11px 20px;border-radius:999px;
     font-size:14.5px;font-weight:500;text-decoration:none;
     border:1px solid var(--borde);color:var(--texto);background:transparent}
.btn:hover{background:var(--superficie)}
.btn-vivo{background:var(--vivo);color:#04121a;border-color:var(--vivo);font-weight:700}
.btn-vivo:hover{background:#3ee0ff}

/* --- Portada --- */
.portada{padding:76px 0 0;overflow:hidden}
.portada .rejilla{display:grid;grid-template-columns:minmax(0,540px) minmax(0,1fr);
                  gap:44px;align-items:center}
h1{font-size:clamp(27px,3.4vw,36px);line-height:1.12;letter-spacing:-0.03em;
   font-weight:700;margin:38px 0 14px}
.portada h1{font-size:clamp(32px,4.3vw,47px);line-height:1.06;
   letter-spacing:-0.033em;margin:0 0 18px}
main{padding-bottom:10px}
.entradilla{font-size:18px;color:var(--tenue);margin:0 0 28px;max-width:46ch}
.acciones{display:flex;gap:11px;flex-wrap:wrap;align-items:center}
.bajo-boton{font-family:var(--mono);font-size:12.5px;color:var(--tenue);margin-top:16px}

/* La captura desborda por la derecha a propósito: es lo único atrevido de la
   página, y es el producto de verdad, no una maqueta dibujada con divs. */
.captura-portada{position:relative}
.captura-portada img{display:block;width:min(1000px,calc(50vw + 260px));
  max-width:none;height:auto;
  border:1px solid var(--borde);border-radius:var(--r-sup) 0 0 var(--r-sup);
  border-right:0}

/* --- Cifras. Sin cajas: espacio y una regla. --- */
.cifras{display:grid;grid-template-columns:repeat(4,1fr);gap:32px;
        border-top:1px solid var(--borde);margin-top:72px;padding:34px 0}
.cifra b{display:block;font-family:var(--mono);font-size:26px;font-weight:400;
         letter-spacing:-0.02em}
.cifra span{display:block;font-size:13.5px;color:var(--tenue);margin-top:3px}

/* --- Secciones --- */
section{padding:60px 0;border-top:1px solid var(--borde)}
section:first-of-type{border-top:0}
h2{font-size:clamp(24px,3vw,31px);line-height:1.15;letter-spacing:-0.028em;
   font-weight:700;margin:0 0 14px}
h3{font-size:18px;letter-spacing:-0.018em;font-weight:700;margin:30px 0 8px}
p{margin:0 0 16px}
a{color:var(--texto);text-decoration:underline;text-decoration-color:var(--borde);
  text-underline-offset:3px}
a:hover{text-decoration-color:var(--tenue)}

/* Máquina frente a persona: mono para lo que escribió un ordenador. */
code,kbd,.mono{font-family:var(--mono);font-size:.895em}
code{background:var(--superficie);border:1px solid var(--borde);
     border-radius:5px;padding:1.5px 6px}
pre{font-family:var(--mono);font-size:13.5px;line-height:1.75;
    background:#05070c;border:1px solid var(--borde);border-radius:var(--r-sup);
    padding:18px 20px;overflow-x:auto;margin:0 0 18px}
pre code{background:none;border:0;padding:0;font-size:inherit}

/* --- Capturas dentro del texto --- */
figure{margin:26px 0}
figure img{display:block;width:100%;border:1px solid var(--borde);
           border-radius:var(--r-sup)}
figcaption{font-size:13.5px;color:var(--tenue);margin-top:9px}

/* --- Pasos. Numerados porque esto SÍ es una secuencia. --- */
.pasos{counter-reset:paso;margin:24px 0 0;padding:0;list-style:none}
.pasos li{counter-increment:paso;position:relative;padding-left:42px;
          margin-bottom:26px}
.pasos li::before{content:counter(paso);position:absolute;left:0;top:1px;
  font-family:var(--mono);font-size:13px;color:var(--tenue);
  border:1px solid var(--borde);border-radius:999px;width:27px;height:27px;
  display:grid;place-items:center}
.pasos h3{margin:0 0 6px;font-size:16.5px}
.pasos p{margin:0 0 10px;color:var(--tenue);font-size:15.5px}

/* --- La sección de lo que no funciona. Misma jerarquía que las demás. --- */
.limites{border-top:1px solid var(--borde);margin-top:20px}
.limites div{border-bottom:1px solid var(--borde);padding:16px 0;
             display:grid;grid-template-columns:190px 1fr;gap:24px}
.limites b{font-weight:500;font-size:15px}
.limites p{margin:0;color:var(--tenue);font-size:15px}

/* --- Piezas del sistema --- */
.piezas{border-top:1px solid var(--borde);margin-top:18px}
.piezas div{border-bottom:1px solid var(--borde);padding:14px 0;
            display:grid;grid-template-columns:170px 1fr;gap:24px;align-items:baseline}
.piezas b{font-family:var(--mono);font-weight:400;font-size:14.5px}
.piezas span{color:var(--tenue);font-size:15px}

/* --- Galería --- */
.galeria{display:grid;grid-template-columns:repeat(2,1fr);gap:20px;margin-top:24px}
.galeria a{display:block;text-decoration:none}
.galeria img{display:block;width:100%;border:1px solid var(--borde);
             border-radius:var(--r-sup)}
.galeria span{display:block;font-size:13.5px;color:var(--tenue);margin-top:8px}

/* --- Índices de documentación --- */
.indice{border-top:1px solid var(--borde);margin-top:18px}
.indice a{display:grid;grid-template-columns:210px 1fr;gap:24px;
          border-bottom:1px solid var(--borde);padding:15px 0;
          text-decoration:none;align-items:baseline}
.indice a:hover{background:var(--superficie)}
.indice b{font-weight:500;font-size:15.5px}
.indice span{color:var(--tenue);font-size:14.5px}

/* --- Aviso --- */
.aviso{border:1px solid var(--borde);border-left:2px solid var(--vivo);
       border-radius:0 var(--r-sup) var(--r-sup) 0;
       background:var(--superficie);padding:16px 20px;margin:22px 0}
.aviso p{margin:0;font-size:15.5px}

footer{border-top:1px solid var(--borde);margin-top:70px;padding:26px 0 44px;
       color:var(--tenue);font-size:13.5px}
footer a{color:var(--tenue)}

/* Tablas de la documentación */
table{border-collapse:collapse;width:100%;margin:0 0 18px;font-size:15px}
th,td{border-bottom:1px solid var(--borde);padding:9px 12px 9px 0;text-align:left}
th{font-weight:500;color:var(--tenue);font-size:13.5px}

/* Teclado visible: quien navega sin ratón tiene que ver dónde está. */
a:focus-visible,.btn:focus-visible{outline:2px solid var(--vivo);outline-offset:3px;
  border-radius:3px}

@media (max-width:900px){
  body{font-size:16px}
  .cont{padding:0 20px}
  .portada{padding:44px 0 0}
  .portada .rejilla{grid-template-columns:1fr;gap:30px}
  .captura-portada img{width:100%;max-width:100%;height:auto;
                       border-right:1px solid var(--borde);
                       border-radius:var(--r-sup)}
  /* La marca en una línea: partida en dos deja la navegación torcida. */
  .marca{white-space:nowrap}
  .enl{white-space:nowrap}
  .cifras{grid-template-columns:repeat(2,1fr);gap:22px;margin-top:46px}
  .galeria{grid-template-columns:1fr}
  .limites div,.piezas div,.indice a{grid-template-columns:1fr;gap:5px}
  nav .cont{gap:18px;overflow-x:auto}
}
@media (prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
CSS

# Dimensiones reales de una captura. Ponerlas a mano en el HTML es pedir que
# se queden desfasadas: en cuanto se recorta una imagen, el navegador reserva
# un hueco del tamaño equivocado y la página da un salto al cargar.
dim() {  # dim <ruta-relativa-a-build/web>
    python3 - "$WEB/$1" <<'PY' 2>/dev/null || echo ''
import sys
try:
    from PIL import Image
    w, h = Image.open(sys.argv[1]).size
    print('width="%d" height="%d"' % (w, h))
except Exception:
    print('')
PY
}

# --- Cabecera y pie compartidos ----------------------------------------------
cabecera() {  # cabecera <titulo> <seccion-activa> <prefijo> [suelto]
    local t="$1" act="$2" pre="$3" suelto="${4:-}"
    cat <<HTML
<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark">
<meta name="description" content="MIKE OS: un sistema operativo construido desde el kernel hacia arriba. Sin systemd, con gestor de paquetes, shell y escritorio propios.">
<meta property="og:title" content="$t">
<meta property="og:description" content="Un sistema operativo construido desde el kernel hacia arriba.">
<meta property="og:image" content="https://m1keos.duckdns.org/capturas/escritorio.png">
<meta property="og:type" content="website">
<title>$t</title>
<link rel="icon" href="${pre}favicon.svg" type="image/svg+xml">
<link rel="preload" href="${pre}tipos/geist-700.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="${pre}estilo.css"></head><body>
<nav><div class="cont">
  <a class="marca" href="${pre}index.html">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 6l6 6-6 6"/><path d="M13 18h7"/></svg>
    MIKE OS</a>
  <a class="enl $([ "$act" = inicio ] && echo aqui)" href="${pre}index.html">Inicio</a>
  <a class="enl $([ "$act" = capturas ] && echo aqui)" href="${pre}capturas/index.html">Capturas</a>
  <a class="enl $([ "$act" = docs ] && echo aqui)" href="${pre}docs/index.html">Documentación</a>
  <a class="enl $([ "$act" = wiki ] && echo aqui)" href="${pre}wiki/index.html">Wiki</a>
  <a class="enl derecha" href="https://github.com/${MIKEOS_REPO_GITHUB:-M1KE-27/m1keos}">Código</a>
  <a class="btn $([ "$act" = descargas ] && echo aqui)" href="${pre}descargas.html">Descargar</a>
</div></nav>
HTML
    # Sin esto, las páginas interiores salían pegadas al borde izquierdo: la
    # portada monta su propio contenedor y el resto se quedó sin ninguno.
    [ "$suelto" = "suelto" ] || echo '<div class="cont"><main>'
}

pie() {  # pie [suelto]
    [ "${1:-}" = "suelto" ] || echo '</main></div>'
    cat <<HTML
<footer><div class="cont">
MIKE OS $VERSION, licencia MIT. Servido desde un mini PC en casa.
Actualizado el $FECHA.
<a href="https://github.com/${MIKEOS_REPO_GITHUB:-M1KE-27/m1keos}">Código en GitHub</a>
</div></footer>
</body></html>
HTML
}

# La cabecera y el pie, volcados a un archivo para que los generadores escritos
# en Python (documentación y wiki) usen EXACTAMENTE los mismos. Antes cada uno
# llevaba su propia copia del HTML de la navegación, y al tocar una el resto se
# quedaba atrás: el índice de documentación seguía enseñando un menú de hace dos
# versiones. Un solo sitio, y se acabó.
for _sec in inicio capturas docs wiki descargas; do
    cabecera "@TITULO@" "$_sec" "@PRE@" > "$WEB/.cabecera-$_sec.html"
done
pie > "$WEB/.pie.html"

# El icono, como SVG: son 200 bytes y la marca del sistema es exactamente esto.
cat > "$WEB/favicon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
     stroke="#00d4ff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
<rect width="24" height="24" rx="5" fill="#090b10" stroke="none"/>
<path d="M5 6l6 6-6 6"/><path d="M13 18h7"/></svg>
SVG

# --- Página de inicio ---------------------------------------------------------
paso "Escribiendo la portada"
{
cabecera "MIKE OS" inicio "" suelto
cat <<HTML
<div class="portada"><div class="cont"><div class="rejilla">
  <div>
    <h1>Escrito desde el kernel hacia arriba.</h1>
    <p class="entradilla">MIKE OS es un sistema operativo completo. Kernel
      propio, sin systemd, gestor de paquetes y escritorio escritos para él.</p>
    <div class="acciones">
      <a class="btn btn-vivo" href="$URL_ISO">Descargar $ETIQUETA_ISO</a>
      <a class="btn" href="docs/instalacion.html">Cómo se instala</a>
    </div>
    <p class="bajo-boton">$ISO_TAM &nbsp;·&nbsp; x86_64 UEFI</p>
  </div>
  <div class="captura-portada">
    <img src="capturas/bienvenida.png" $(dim capturas/bienvenida.png)
         alt="El escritorio de MIKE OS con la ventana de bienvenida abierta">
  </div>
</div>

<div class="cifras">
  <div class="cifra"><b>0,59 s</b><span>del kernel a la consola</span></div>
  <div class="cifra"><b>324 MB</b><span>de RAM con el escritorio</span></div>
  <div class="cifra"><b>25 s</b><span>en compilar el sistema</span></div>
  <div class="cifra"><b>0</b><span>líneas de systemd</span></div>
</div>
</div></div>

<div class="cont">

<section>
  <div class="prosa">
    <h2>Qué hay aquí dentro</h2>
    <p>MIKE OS no es una distribución con otro tema encima. El kernel se
      configura y se compila aquí, el init es runit, y el gestor de paquetes, la
      shell, la terminal y el escritorio están escritos para este sistema.</p>
  </div>
  <div class="piezas">
    <div><b>kernel $KVER</b><span>configurado a mano, con arranque UEFI propio y btrfs dentro</span></div>
    <div><b>runit</b><span>el init. Arranca los servicios y los vigila; si uno se cae, vuelve</span></div>
    <div><b>mpm</b><span>gestor de paquetes con instantáneas antes de cada cambio y vuelta atrás</span></div>
    <div><b>mkshell</b><span>la shell del sistema</span></div>
    <div><b>Hyprland + Quickshell</b><span>el compositor y una barra escrita en QML para esto</span></div>
    <div><b>$N_PKG paquetes</b><span>en el repositorio propio</span></div>
  </div>
</section>

<section>
  <div class="prosa">
    <h2>Se instala desde una interfaz, no desde la terminal</h2>
    <p>Hasta la versión anterior había que saber que existía una orden llamada
      <code>m-install</code>. Ahora hay un instalador gráfico: detecta el disco
      solo, te enseña qué hay dentro y te avisa de qué vas a borrar antes de
      borrarlo.</p>
  </div>

  <figure>
    <img src="capturas/instalador-disco.png" $(dim capturas/instalador-disco.png)
         alt="El instalador enseñando el disco, las particiones y el aviso de lo que se va a borrar">
    <figcaption>Detecta el disco, lista sus particiones con el sistema que hay en
      cada una, y avisa en ámbar de lo que se va a perder. Si algo impediría que
      el equipo arrancara despu&eacute;s, no deja continuar y explica por qué.</figcaption>
  </figure>

  <div class="prosa">
    <h3>Instalar al lado de Windows</h3>
    <p>Usa el espacio libre y no toca nada de lo que ya hay. La partición EFI que
      encuentre se conserva tal cual, con el arranque de Windows dentro: eso es
      lo que hace que Windows siga apareciendo en el menú en vez de
      «desaparecer». Al terminar, GRUB lo añade solo.</p>

    <h3>Alguien puede ayudarte desde su casa</h3>
    <p>Si te atascas instalando, el paso de red enciende SSH, crea una cuenta
      temporal de cuatro letras y te enseña la orden exacta y la contraseña para
      dictársela por teléfono. Al desactivarlo, la cuenta se borra.</p>
  </div>

  <figure>
    <img src="capturas/instalador-red.png" $(dim capturas/instalador-red.png)
         alt="El paso de red del instalador, con la tarjeta de ayuda remota">
    <figcaption>En inglés por defecto, con español a un clic.</figcaption>
  </figure>
</section>

<section>
  <div class="prosa">
    <h2>Grabarlo y arrancar</h2>
  </div>
  <ol class="pasos">
    <li>
      <h3>Grabar la imagen en un USB</h3>
      <p>Comprueba la letra del dispositivo antes de ejecutarlo: esto borra el
        USB entero.</p>
      <pre><code>sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync</code></pre>
    </li>
    <li>
      <h3>Desactivar Secure Boot</h3>
      <p>El kernel no lleva la firma de Microsoft, así que la firmware se niega a
        arrancarlo con Secure Boot activo. En la mayoría de equipos se desactiva
        entrando en la configuración de la placa al encender.</p>
    </li>
    <li>
      <h3>Probar, y luego instalar si convence</h3>
      <p>El USB arranca a un escritorio completo que corre en memoria: no toca tu
        disco. Cuando quieras instalarlo, el botón está en la ventana de
        bienvenida.</p>
    </li>
  </ol>
</section>

<section>
  <div class="prosa">
    <h2>Lo que todavía no funciona</h2>
    <p>Esto es una versión alpha y esta lista es parte de la documentación, no
      una nota al pie. Si algo de aquí te bloquea, mejor saberlo ahora que con el
      disco a medio formatear.</p>
  </div>
  <div class="limites">
    <div><b>Secure Boot</b><p>Hay que desactivarlo. El kernel no está firmado por Microsoft y no lo va a estar pronto.</p></div>
    <div><b>Sólo UEFI</b><p>No arranca por BIOS ni con CSM. En equipos anteriores a 2012 no va a funcionar.</p></div>
    <div><b>Particionado manual</b><p>El instalador sabe borrar, instalar al lado y reemplazar. Para crear o redimensionar a mano, trae GParted con <code>mpm install gparted</code>.</p></div>
    <div><b>Privilegios</b><p><code>m-sudo</code> da root a la cuenta sin pedir contraseña. La pantalla de bloqueo protege de miradas, no de alguien con tiempo y teclado.</p></div>
    <div><b>Hardware real</b><p>Probado en QEMU con firmware UEFI de verdad. En portátiles físicos está sin probar: esta versión existe para eso.</p></div>
  </div>
</section>

<section>
  <div class="prosa"><h2>El escritorio</h2>
  <p>La barra y el Centro de Control están escritos en QML para este sistema. Se
    puede mover la barra a cualquier borde, cambiar su forma y elegir qué módulos
    lleva. El fondo de pantalla puede teñir la paleta entera, terminal incluida.</p>
  </div>
  <div class="galeria">
    <a href="capturas/centro-de-control.png"><img $(dim capturas/centro-de-control.png) src="capturas/centro-de-control.png" alt="El Centro de Control de MIKE OS" loading="lazy"><span>El Centro de Control</span></a>
    <a href="capturas/bloqueo.png"><img $(dim capturas/bloqueo.png) src="capturas/bloqueo.png" alt="La pantalla de bloqueo" loading="lazy"><span>La pantalla de bloqueo</span></a>
    <a href="capturas/terminal.png"><img $(dim capturas/terminal.png) src="capturas/terminal.png" alt="La terminal de MIKE OS" loading="lazy"><span>La terminal</span></a>
    <a href="capturas/grub.png"><img $(dim capturas/grub.png) src="capturas/grub.png" alt="El menú de arranque de MIKE OS" loading="lazy"><span>El menú de arranque</span></a>
  </div>
  <p style="margin-top:22px"><a href="capturas/index.html">Ver todas las capturas</a></p>
</section>

</div>
HTML
pie suelto
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
  <tr><td>mikeos.iso</td><td>$ISO_TAM</td><td>$KVER</td></tr>
</table>
<p class="tenue">SHA256:<br><code style="font-size:11px;word-break:break-all">$ISO_SHA</code></p>
<p style="margin:22px 0 8px"><a class="btn btn-vivo" href="$URL_ISO">Descargar mikeos.iso</a></p>
<p class="tenue">La descarga la sirve GitHub y empieza al pulsar, sin página
intermedia. Se hace así porque esta web vive en un mini PC de casa: su línea da
unos 780 KB/s de subida, o sea casi cuatro minutos por descarga y de una en
una. Los paquetes, que son pequeños, sí salen de aquí.</p>

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
<p><a href="docs/instalacion.html">Guía de instalación completa</a></p>
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
    """Monta la página con la MISMA cabecera y el mismo pie que el resto.

    Se leen de los archivos que dejó el script de shell en vez de repetir aquí
    el HTML de la navegación. Cuando había dos copias, tocar una dejaba la otra
    atrás sin que nadie se enterara: el índice de documentación estuvo
    enseñando un menú de dos versiones antes."""
    cab = open(os.path.join(web, ".cabecera-%s.html" % activa)).read()
    cab = cab.replace("@TITULO@", "%s · MIKE OS" % titulo).replace("@PRE@", pre)
    pie_html = open(os.path.join(web, ".pie.html")).read().replace("@PRE@", pre)
    return cab + cuerpo + pie_html

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

# Una sola línea por documento, con su descripción al lado. Antes cada uno
# iba en una tarjeta con su borde y su sombra: nueve cajas idénticas en fila
# que no decían nada que la lista no dijera igual de bien y con menos ruido.
DESCRIPCIONES = {
    "architecture": "Cómo encajan las piezas: kernel, init, servicios y escritorio.",
    "benchmarks":   "Cuánto tarda en arrancar y cuánta memoria gasta, medido.",
    "boot":         "Del firmware UEFI al escritorio, paso por paso.",
    "desktop":      "Hyprland, la barra de Quickshell y el Centro de Control.",
    "development":  "Compilar el sistema, probarlo en una máquina virtual y depurarlo.",
    "kernel":       "Qué se activa en la configuración del kernel y por qué.",
    "mcore":        "Las herramientas m-* que trae el sistema.",
    "mkshell":      "La shell escrita para MIKE OS.",
    "mpm":          "El gestor de paquetes, las instantáneas y la vuelta atrás.",
    "networking":   "Cable, WiFi y qué hacer cuando no hay red.",
    "recovery":     "Qué hacer cuando el equipo no arranca.",
    "runit":        "El init y la supervisión de servicios.",
    "ssh":          "Entrar desde otro equipo.",
}
enlaces = "\n".join(
    '<a href="%s.html"><b>%s</b><span>%s</span></a>'
    % (b, t, DESCRIPCIONES.get(b, ""))
    for b, t in generadas)
indice = f'''<header><h1>Documentación</h1>
<p class="lema">Cómo está hecho MIKE OS por dentro. Se genera desde el propio
repositorio, así que no puede quedarse vieja.</p></header>
<h2>Empezar por aquí</h2>
<div class="indice">
  <a href="instalacion.html"><b>Instalación</b><span>Del USB al primer arranque.</span></a>
  <a href="actualizaciones.html"><b>Actualizaciones</b><span>Cómo llega a tu equipo lo que cambia.</span></a>
</div>
<h2>El sistema por dentro</h2>
<div class="indice">
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
cabecera "Capturas · MIKE OS" capturas "../"
cat <<'HTML'
<header><h1>Capturas</h1>
<p class="lema">Sacadas del sistema recién construido y en marcha, no de un
montaje. Si el escritorio cambia, estas cambian con él en la siguiente
compilación.</p></header>
<h2>El escritorio</h2>
HTML
# La lista va aquí y no repartida por el script: añadir una captura es añadir
# una línea. Formato  archivo:pie de foto
for par in "escritorio:El escritorio con el fondo del sistema" \
           "bienvenida:La ventana de bienvenida, la primera vez que arranca" \
           "centro-de-control:El Centro de Control" \
           "ajustes-barra:Ajustes de la barra: posición, forma y qué módulos lleva" \
           "ajustes-bloqueo:Ajustes del bloqueo, con lo que aún no hace dicho a las claras" \
           "terminal:La terminal" \
           "bloqueo:La pantalla de bloqueo, con el fondo desenfocado detrás"; do
    n="${par%%:*}"; d="${par#*:}"
    [ -f "$WEB/capturas/$n.png" ] || continue
    printf '<figure><img %s src="%s.png" alt="%s" loading="lazy"><figcaption>%s</figcaption></figure>\n' \
        "$(dim capturas/$n.png)" "$n" "$d" "$d"
done
echo '<h2>El instalador</h2>'
for par in "instalador-idioma:Empieza en inglés, con español a un clic" \
           "instalador-red:El paso de red, con la ayuda remota por SSH" \
           "instalador-disco:El disco: qué hay dentro y qué se va a borrar" \
           "instalador-cuenta:Nombre del equipo y contraseña" \
           "instalador-aspecto:El fondo se elige antes de instalar" \
           "instalador-resumen:Lo último que se ve antes de que algo sea irreversible"; do
    n="${par%%:*}"; d="${par#*:}"
    [ -f "$WEB/capturas/$n.png" ] || continue
    printf '<figure><img %s src="%s.png" alt="%s" loading="lazy"><figcaption>%s</figcaption></figure>\n' \
        "$(dim capturas/$n.png)" "$n" "$d" "$d"
done
echo '<h2>El arranque</h2>'
if [ -f "$WEB/capturas/grub.png" ]; then
    printf '<figure><img %s src="grub.png" alt="%s" loading="lazy"><figcaption>%s</figcaption></figure>\n' \
        "$(dim capturas/grub.png)" \
        "El menú de arranque de MIKE OS" \
        "El menú de GRUB con el tema del sistema. Si hay otro sistema operativo en el equipo, aparece aquí."
fi
pie
} > "$WEB/capturas/index.html"
verde "  galería"

# --- La ISO -------------------------------------------------------------------
# La ISO ya no se copia al servidor: son 175 MB que tardarían casi cuatro
# minutos en subir por la línea de casa en cada publicación, para servir algo
# que GitHub sirve mejor. Sólo se deja el SHA256, que pesa nada y es lo que
# permite comprobar la descarga.
if [ "$HAY_ISO" -eq 1 ] && [ -f "$ISO.sha256" ]; then
    cp "$ISO.sha256" "$WEB/descargas/mikeos.iso.sha256"
fi
rm -f "$WEB/descargas/mikeos.iso"

echo
verde "Web generada en $WEB"

# Las plantillas de cabecera y pie son andamio del generador, no contenido.
rm -f "$WEB"/.cabecera-*.html "$WEB/.pie.html"

# --- Subir --------------------------------------------------------------------
if [ "$SUBIR" -eq 1 ]; then
    echo
    exigir_servidor
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
