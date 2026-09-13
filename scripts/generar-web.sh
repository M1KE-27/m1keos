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
# La misma fecha en inglés, para el pie de las páginas en ese idioma. Se calcula
# aquí y no dentro de t(): "date" con otro idioma exige tocar LC_TIME, y hacerlo
# en medio de la generación afectaría a todo lo que venga detrás.
FECHA_EN="$(LC_ALL=C date +'%B %-d, %Y')"
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

/* ---------------------------------------------------------------------------
   COLOR
   ---------------------------------------------------------------------------
   Los colores oscuros son los del escritorio (build/desktop/quickshell/
   Paleta.qml). Para el sitio de un sistema operativo, la fuente honesta de
   color es el propio sistema: lo que se ve aquí es lo que se ve al arrancarlo.

   Hasta ahora el sitio era SÓLO oscuro, y había colores escritos a pelo por
   media hoja (#05070c en los bloques de código, un rgba en la navegación).
   Quien entraba de día con el móvil se comía un fondo negro sin alternativa, y
   añadir un tema claro era imposible sin cazar esos valores sueltos uno a uno.
   Ahora TODO color sale de una variable, y hay tres estados:

     :root                        el tema claro, que es el valor por defecto
     prefers-color-scheme:dark    lo que pida el sistema de quien mira
     [data-tema="claro"|"oscuro"] lo que haya elegido a mano, que gana

   La regla que separa esto del "dark tech" de plantilla sigue intacta: el
   acento SÓLO para lo que está vivo. En toda la página aparece en cinco sitios
   contados. El color lo ponen las capturas, no la decoración. */
:root{
  --lienzo:#fbfbfd;
  --lienzo-nav:rgba(251,251,253,.82);
  --superficie:#f1f2f6;
  --hundido:#eef0f4;
  --borde:#dfe2e9;
  --borde-fuerte:#c8ccd6;
  --texto:#10141b;
  --tenue:#5c6472;
  --vivo:#0077a8;
  --vivo-claro:#005f88;
  --sobre-vivo:#ffffff;
  --sombra:0 1px 2px rgba(16,20,27,.05),0 8px 24px rgba(16,20,27,.06);

  --sans:Geist,ui-sans-serif,system-ui,sans-serif;
  --mono:"JB Mono",ui-monospace,SFMono-Regular,monospace;

  /* Una sola escala de radios, documentada: reglas estructurales a 0,
     superficies e imágenes a 10, cosas pulsables en cápsula. */
  --r-sup:10px;
}

/* El tema oscuro: los colores del escritorio de verdad. */
@media (prefers-color-scheme:dark){
  :root:not([data-tema="claro"]){
    --lienzo:#090b10;
    --lienzo-nav:rgba(9,11,16,.86);
    --superficie:#12161d;
    --hundido:#05070c;
    --borde:#232a35;
    --borde-fuerte:#333c4a;
    --texto:#e8ebf0;
    --tenue:#79818f;
    --vivo:#00d4ff;
    --vivo-claro:#3ee0ff;
    --sobre-vivo:#04121a;
    --sombra:0 1px 2px rgba(0,0,0,.4),0 10px 30px rgba(0,0,0,.35);
  }
}
/* Y el mismo tema cuando se elige a mano, que manda sobre lo que diga el
   sistema. Va repetido a propósito: una variable definida SÓLO dentro de un
   media query deja de existir en cuanto el media query no aplica, y entonces
   el botón de cambiar tema no puede hacer nada. */
:root[data-tema="oscuro"]{
  --lienzo:#090b10;
  --lienzo-nav:rgba(9,11,16,.86);
  --superficie:#12161d;
  --hundido:#05070c;
  --borde:#232a35;
  --borde-fuerte:#333c4a;
  --texto:#e8ebf0;
  --tenue:#79818f;
  --vivo:#00d4ff;
  --vivo-claro:#3ee0ff;
  --sobre-vivo:#04121a;
  --sombra:0 1px 2px rgba(0,0,0,.4),0 10px 30px rgba(0,0,0,.35);
}

*{box-sizing:border-box}
/* Ninguna imagen desborda su sitio ni se deforma. Va aquí arriba y sin
   excepciones: cada vez que una regla concreta ponía "max-width:none" para
   conseguir un efecto, la imagen acababa recortada a algún ancho intermedio
   que nadie había mirado. height:auto es obligatorio porque el atributo
   height="900" del HTML hace de altura CSS en cuanto se toca el ancho. */
img{display:block;max-width:100%;height:auto}
html{-webkit-text-size-adjust:100%}
body{
  margin:0;background:var(--lienzo);color:var(--texto);
  font-family:var(--sans);font-size:17px;line-height:1.65;
  font-weight:400;letter-spacing:-0.003em;
  -webkit-font-smoothing:antialiased;
}
::selection{background:var(--vivo);color:var(--sobre-vivo)}

.cont{max-width:1180px;margin:0 auto;padding:0 32px}
.prosa{max-width:68ch}

/* --- Navegación. Una línea, 64 px, sin excepciones. --- */
nav{border-bottom:1px solid var(--borde);position:sticky;top:0;z-index:10;
    background:var(--lienzo-nav);backdrop-filter:blur(14px)}
nav .cont{display:flex;align-items:center;gap:28px;height:64px}
.marca{display:flex;align-items:center;gap:9px;color:var(--texto);
       text-decoration:none;font-weight:700;letter-spacing:-0.02em;margin-right:8px}
.marca svg{width:17px;height:17px;flex:none}
.enl{color:var(--tenue);text-decoration:none;font-size:14.5px;font-weight:500}
.enl:hover{color:var(--texto)}
.enl.aqui{color:var(--texto)}
nav .derecha{margin-left:auto}

/* --- El menú, detrás de un botón. También en escritorio. ---
   La barra llevaba seis enlaces, el idioma, el tema y el botón de descargar:
   nueve cosas compitiendo por la atención, y ninguna de ellas es a lo que
   viene la gente. Ahora quedan tres --- idioma, tema y descargar --- y el
   resto entra por el botón.
   No se oculta sólo en el móvil a propósito: dos navegaciones distintas según
   el ancho son dos navegaciones que hay que mantener, y la de escritorio
   siempre acaba siendo la que nadie prueba. */
.hamburguesa{width:34px;height:34px;flex:none;display:grid;place-content:center;
  gap:4px;border:1px solid var(--borde);border-radius:999px;background:transparent;
  cursor:pointer;padding:0 9px}
.hamburguesa span{display:block;width:16px;height:1.5px;background:var(--tenue);
  border-radius:2px;transition:transform .18s,opacity .18s,background .15s}
.hamburguesa:hover{border-color:var(--borde-fuerte)}
.hamburguesa:hover span{background:var(--texto)}
/* Abierto, las tres rayas se convierten en una equis: dice que el mismo botón
   cierra, sin tener que poner una segunda equis en el panel. */
.hamburguesa[aria-expanded="true"] span:nth-child(1){transform:translateY(5.5px) rotate(45deg)}
.hamburguesa[aria-expanded="true"] span:nth-child(2){opacity:0}
.hamburguesa[aria-expanded="true"] span:nth-child(3){transform:translateY(-5.5px) rotate(-45deg)}

.menu{border-top:1px solid var(--borde);background:var(--lienzo);
      box-shadow:var(--sombra)}
/* La lista NO reutiliza ".cont", y no es un capricho.
   El panel vive dentro de <nav>, así que "nav .cont" --- que vale
   "height:64px; align-items:center" para la barra --- le caía encima: el panel
   se quedaba en 64 px de alto, recortando todos los enlaces menos el primero, y
   con el texto centrado. Desde fuera parecía que el menú estaba a medio hacer.
   Una clase propia y el problema no puede volver. */
.menu-lista{display:flex;flex-direction:column;align-items:stretch;
  max-width:1180px;margin:0 auto;padding:10px 32px 14px}
/* La separación va ENTRE enlaces, no debajo de cada uno.
   Con "border-bottom" + ":last-child{border:0}" quedaba una raya suelta bajo el
   último enlace visible en escritorio: el de idioma es el último hijo pero está
   oculto ahí, así que ":last-child" limpiaba el borde de un elemento que no se
   ve y dejaba el del anterior puesto. */
.menu a{color:var(--tenue);text-decoration:none;font-size:15px;font-weight:500;
        padding:11px 0}
.menu a + a{border-top:1px solid var(--borde)}
.menu a:hover{color:var(--texto)}
.menu a.aqui{color:var(--texto)}
/* El idioma ya está en la barra cuando hay sitio; dentro del menú sólo hace
   falta en pantallas donde se ha quitado de ahí. */
.menu .solo-estrecho{display:none}

/* En escritorio el panel no ocupa el ancho entero: una tarjeta a la derecha,
   bajo el botón que lo abrió, que es de donde el ojo viene. */
@media (min-width:901px){
  .menu{position:absolute;right:max(32px,calc((100vw - 1180px) / 2 + 32px));
        top:calc(100% - 1px);width:230px;border:1px solid var(--borde);
        border-radius:var(--r-sup);overflow:hidden}
  .menu-lista{max-width:none;margin:0;padding:6px 18px 10px}
  nav{position:sticky}
}
/* El selector de idioma va escrito EN EL IDIOMA AL QUE LLEVA ("Read in
   English" en la página española). Un icono de globo o las siglas "EN/ES" no
   dicen nada a quien no sabe ya lo que va a pasar; la frase en el otro idioma
   la entiende justo quien la necesita. */
.idioma{white-space:nowrap}

/* El botón de tema. Un cuadrado del alto de un botón, con los dos iconos
   dentro y sólo uno visible: así no cambia de tamaño al pulsarlo y la
   navegación no da un salto. */
.tema{width:34px;height:34px;flex:none;display:grid;place-items:center;
      border:1px solid var(--borde);border-radius:999px;background:transparent;
      color:var(--tenue);cursor:pointer;padding:0}
.tema:hover{color:var(--texto);border-color:var(--borde-fuerte)}
.tema svg{width:15px;height:15px}
.tema .luna{display:none}
.tema .sol{display:block}
@media (prefers-color-scheme:dark){
  :root:not([data-tema="claro"]) .tema .luna{display:block}
  :root:not([data-tema="claro"]) .tema .sol{display:none}
}
:root[data-tema="oscuro"] .tema .luna{display:block}
:root[data-tema="oscuro"] .tema .sol{display:none}
:root[data-tema="claro"] .tema .luna{display:none}
:root[data-tema="claro"] .tema .sol{display:block}

/* --- Botones. Cápsula, y sólo el primario lleva el acento. --- */
.btn{display:inline-flex;align-items:center;gap:9px;padding:11px 20px;
     border-radius:999px;font-size:14.5px;font-weight:500;text-decoration:none;
     border:1px solid var(--borde);color:var(--texto);background:transparent;
     transition:background .15s,border-color .15s}
.btn:hover{background:var(--superficie);border-color:var(--borde-fuerte)}
.btn-vivo{background:var(--vivo);color:var(--sobre-vivo);border-color:var(--vivo);font-weight:700}
.btn-vivo:hover{background:var(--vivo-claro);border-color:var(--vivo-claro)}
/* El tamaño del archivo va DENTRO del botón de descarga: quien lo mira está
   decidiendo si se lo baja, y el dato que necesita para decidir es ese. */
.btn .peso{font-family:var(--mono);font-size:12px;opacity:.72;font-weight:400}

/* --- Portada --- */
/* La captura va DEBAJO del texto, no al lado.
   En dos columnas nunca tiene sitio: a 1150 px de ancho le tocaban 350, o sea
   un 22% de escala, y encima desbordaba su celda y se veía sólo la mitad
   izquierda. Una captura de un escritorio necesita ancho o no se entiende.
   Debajo se lleva la página entera y se ve completa a cualquier tamaño. */
.portada{padding:74px 0 0;position:relative;overflow:hidden}
/* Un resplandor del color del sistema detrás del titular. Muy tenue y muy
   grande: no se ve como una mancha, se nota como que la página tiene fondo.
   Va en un pseudoelemento para que no capture ni un clic. */
.portada::before{content:"";position:absolute;inset:-40% 0 auto 50%;
  width:1100px;height:640px;transform:translateX(-50%);pointer-events:none;
  background:radial-gradient(50% 50% at 50% 50%,var(--vivo) 0,transparent 72%);
  opacity:.07}
.portada .cont{position:relative}
h1{font-size:clamp(27px,3.4vw,36px);line-height:1.12;letter-spacing:-0.03em;
   font-weight:700;margin:38px 0 14px}
.portada h1{font-size:clamp(32px,4.6vw,52px);line-height:1.05;
   letter-spacing:-0.034em;margin:0 0 18px;max-width:16ch}
main{padding-bottom:10px}
.entradilla{font-size:18px;color:var(--tenue);margin:0 0 28px;max-width:52ch}
.acciones{display:flex;gap:11px;flex-wrap:wrap;align-items:center}
.bajo-boton{font-family:var(--mono);font-size:12.5px;color:var(--tenue);margin-top:16px}

/* La chapa de versión, encima del titular. Dice la versión Y que es alpha en
   el mismo sitio: son el mismo dato para quien decide si instalarlo. */
.chapa{display:inline-flex;align-items:center;gap:9px;margin:0 0 22px;
       padding:5px 13px 5px 9px;border:1px solid var(--borde);border-radius:999px;
       font-size:13px;color:var(--tenue);background:var(--superficie)}
.chapa .punto{width:6px;height:6px;border-radius:999px;background:var(--vivo);flex:none}
.chapa b{font-family:var(--mono);font-weight:400;color:var(--texto)}
.chapa .sep{color:var(--borde-fuerte)}

.captura-portada{margin-top:46px}
.captura-portada img{width:100%;
  border:1px solid var(--borde);border-radius:var(--r-sup);box-shadow:var(--sombra)}

/* A partir de este ancho sobra sitio: la captura se sale hasta el borde
   derecho de la ventana. Se sigue viendo ENTERA; lo único que cambia es
   cuánto ocupa. El cálculo es el hueco que deja el contenedor centrado
   (1180 px de ancho máximo más sus 32 de margen interior). */
@media (min-width:1280px){
  .captura-portada{margin-right:calc((100vw - 1180px) / -2 - 32px)}
  .captura-portada img{border-radius:var(--r-sup) 0 0 var(--r-sup);border-right:0}
}

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
a{color:var(--texto);text-decoration:underline;text-decoration-color:var(--borde-fuerte);
  text-underline-offset:3px}
a:hover{text-decoration-color:var(--tenue)}

/* Un rótulo pequeño encima de un título, para situar la sección sin gastar
   una línea de titular en ello. */
.rotulo{font-family:var(--mono);font-size:12px;letter-spacing:.04em;
        color:var(--vivo);margin:0 0 10px;text-transform:uppercase}

/* Máquina frente a persona: mono para lo que escribió un ordenador. */
code,kbd,.mono{font-family:var(--mono);font-size:.895em}
code{background:var(--superficie);border:1px solid var(--borde);
     border-radius:5px;padding:1.5px 6px;
     /* Un nombre de orden partido por la mitad, con el borde cortado a mitad
        de palabra, se lee como dos cosas distintas: "sftp-" y "server". */
     white-space:nowrap}
/* Dentro de una tarjeta el fondo ya es "superficie": el código tiene que
   hundirse, no confundirse con ella. */
.nuevo code{background:var(--hundido)}
/* Y en una pantalla estrecha, antes de que una orden larga desborde la caja,
   que se pueda arrastrar. */
@media (max-width:480px){code{white-space:normal;word-break:break-word}}
pre{font-family:var(--mono);font-size:13.5px;line-height:1.75;
    background:var(--hundido);border:1px solid var(--borde);border-radius:var(--r-sup);
    padding:18px 20px;overflow-x:auto;margin:0 0 18px}
pre code{background:none;border:0;padding:0;font-size:inherit}

/* --- Capturas dentro del texto --- */
figure{margin:26px 0}
figure img{display:block;width:100%;border:1px solid var(--borde);
           border-radius:var(--r-sup)}
figcaption{font-size:13.5px;color:var(--tenue);margin-top:9px}

/* --- Novedades. Tarjetas, porque son cosas distintas entre sí y sin orden:
       una lista numerada prometería una secuencia que no existe. --- */
/* Cada tarjeta lleva SU borde, y la separación es separación de verdad.
   La primera versión usaba el truco de siempre --- rejilla con fondo del color
   del borde y huecos de 1 px --- y con seis tarjetas en cuatro columnas
   quedaban dos celdas vacías pintadas de gris: desde fuera, una tarjeta rota.
   El truco sólo funciona cuando el número de tarjetas encaja justo con el de
   columnas, o sea nunca después de añadir la séptima. */
.nuevo{display:grid;grid-template-columns:repeat(auto-fit,minmax(268px,1fr));
       gap:14px;margin-top:26px}
.nuevo>div{background:var(--superficie);border:1px solid var(--borde);
           border-radius:var(--r-sup);padding:22px 20px}
.nuevo b{display:block;font-size:16px;letter-spacing:-0.015em;margin-bottom:7px}
.nuevo p{margin:0;color:var(--tenue);font-size:15px;line-height:1.6}
.nuevo .marca-nueva{display:inline-block;font-family:var(--mono);font-size:11px;
  color:var(--vivo);border:1px solid var(--vivo);border-radius:999px;
  padding:0 7px;margin-bottom:11px;opacity:.85}

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
             border-radius:var(--r-sup);transition:border-color .15s,transform .15s}
.galeria a:hover img{border-color:var(--borde-fuerte);transform:translateY(-2px)}
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
a:focus-visible,.btn:focus-visible,.tema:focus-visible{
  outline:2px solid var(--vivo);outline-offset:3px;border-radius:3px}

@media (max-width:900px){
  body{font-size:16px}
  .cont{padding:0 20px}
  .portada{padding:40px 0 0}
  .captura-portada{margin-top:34px}
  /* La marca en una línea: partida en dos deja la navegación torcida. */
  .marca{white-space:nowrap}
  .enl{white-space:nowrap}
  .cifras{grid-template-columns:repeat(2,1fr);gap:22px;margin-top:46px}
  .galeria{grid-template-columns:1fr}
  .limites div,.piezas div,.indice a{grid-template-columns:1fr;gap:5px}
  nav .cont{gap:16px}
  .tema,.hamburguesa,nav .btn{flex:none}
  .menu-lista{padding-left:20px;padding-right:20px}
}
/* En pantallas estrechas de verdad, los enlaces del medio sobran: el logo
   lleva a inicio y el botón de descargar es lo que casi todo el mundo busca.
   Se ocultan en vez de dejar una barra que hay que arrastrar para usarla. */
@media (max-width:560px){
  nav .cont{gap:12px;overflow:visible}
  /* Aquí ya no cabe la frase entera ("Read in English"), así que el idioma
     sale de la barra y entra en el menú, donde sí cabe escrito. Poner ahí
     "EN/ES" para ganar sitio sería ahorrar dos centímetros a cambio de que no
     lo entienda justo quien lo necesita. */
  nav .idioma{display:none}
  .menu .solo-estrecho{display:block}
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

# --- Idiomas ------------------------------------------------------------------
#
# El sitio se publica en dos idiomas, y como DOS ÁRBOLES DE PÁGINAS ESTÁTICAS:
# el español en la raíz y el inglés bajo /en/. No con JavaScript que cambia los
# textos al vuelo.
#
# El motivo es que un sistema operativo se busca, se enlaza y se cita. Con
# páginas de verdad por idioma, cada una tiene su URL, su <html lang> y su
# <link rel="alternate" hreflang>, así que un buscador puede ofrecer la inglesa
# a quien busca en inglés y alguien puede enlazar directamente la que quiere.
# Con textos intercambiados por JavaScript no existe más que una página --- la
# española --- y el resto es humo: no se puede enlazar, no se indexa, y quien
# tenga el JavaScript bloqueado se queda sin nada.
#
# La documentación técnica (docs/) ya está escrita en inglés y se comparte entre
# los dos: traducirla a dos idiomas y mantener las dos al día es exactamente la
# forma de acabar con una de las dos mintiendo.
IDIOMAS="es en"

# t <clave> -- el texto en el idioma activo ($L).
#
# Los dos idiomas van EN LA MISMA LÍNEA a propósito. Con un archivo por idioma,
# añadir una frase en uno y olvidarla en el otro no se ve; aquí, un "case" sin
# su pareja canta a la primera.
t() {
    case "$1" in
    nav.inicio)      [ "$L" = en ] && echo "Home"            || echo "Inicio" ;;
    nav.capturas)    [ "$L" = en ] && echo "Screenshots"     || echo "Capturas" ;;
    nav.docs)        [ "$L" = en ] && echo "Docs"            || echo "Documentación" ;;
    nav.wiki)        [ "$L" = en ] && echo "Wiki"            || echo "Wiki" ;;
    nav.codigo)      [ "$L" = en ] && echo "Source"          || echo "Código" ;;
    nav.descargar)   [ "$L" = en ] && echo "Download"        || echo "Descargar" ;;
    nav.tema)        [ "$L" = en ] && echo "Switch theme"    || echo "Cambiar de tema" ;;
    nav.idioma)      [ "$L" = en ] && echo "Ver en español"  || echo "Read in English" ;;
    nav.menu)        [ "$L" = en ] && echo "Menu"            || echo "Menú" ;;

    meta.desc)       [ "$L" = en ] \
        && echo "MIKE OS: an operating system built from the kernel up. No systemd, with its own package manager, shell and desktop." \
        || echo "MIKE OS: un sistema operativo construido desde el kernel hacia arriba. Sin systemd, con gestor de paquetes, shell y escritorio propios." ;;
    meta.og)         [ "$L" = en ] \
        && echo "An operating system built from the kernel up." \
        || echo "Un sistema operativo construido desde el kernel hacia arriba." ;;

    pie.licencia)    [ "$L" = en ] \
        && echo "MIKE OS $VERSION, MIT licence. Served from a mini PC at home." \
        || echo "MIKE OS $VERSION, licencia MIT. Servido desde un mini PC en casa." ;;
    pie.actualizado) [ "$L" = en ] && echo "Updated on $FECHA_EN." || echo "Actualizado el $FECHA." ;;
    pie.codigo)      [ "$L" = en ] && echo "Source on GitHub" || echo "Código en GitHub" ;;
    *)               echo "$1" ;;
    esac
}

# La ruta de ESTA página en el otro idioma, para el selector. Se pone antes de
# llamar a cabecera; si se deja vacía, el selector lleva a la portada del otro
# idioma, que es lo correcto para las páginas que sólo existen en uno.
ALTERNA=""

# --- Cabecera y pie compartidos ----------------------------------------------
cabecera() {  # cabecera <titulo> <seccion-activa> <prefijo> [suelto]
    #
    # "$pre" es la ruta hasta la RAÍZ DEL SITIO, y sirve para lo que se comparte
    # entre idiomas: la hoja de estilo, el icono, las tipografías, las capturas,
    # la documentación y la wiki.
    #
    # Pero las páginas que SÍ tienen versión por idioma --- la portada y las
    # descargas --- no viven en la raíz del sitio: viven en la raíz de SU
    # idioma. Desde /en/index.html, "Inicio" tiene que llevar a /en/index.html,
    # no a /index.html, o pulsar el logotipo te saca del inglés sin avisar. Eso
    # es exactamente lo que pasaba: la navegación inglesa entera apuntaba a las
    # páginas españolas.
    #
    # De ahí las dos rutas. "$pre" para lo compartido, "$pre_idioma" para lo
    # que está traducido.
    local ti="$1" act="$2" pre="$3" suelto="${4:-}"
    # Las páginas traducidas viven junto a su idioma; las compartidas (docs,
    # wiki, capturas) se sirven en inglés, así que su "Inicio" lleva a /en/.
    local pre_idioma
    if [ "$L" = en ]; then
        case "$act" in
            inicio|descargas) pre_idioma="" ;;   # ya estamos dentro de /en/
            *)                pre_idioma="${pre}en/" ;;
        esac
    else
        pre_idioma="$pre"
    fi
    local otro alt_href
    if [ "$L" = en ]; then otro=es; else otro=en; fi
    alt_href="${ALTERNA:-}"
    if [ -z "$alt_href" ]; then
        # "$pre" ya apunta a la raíz del sitio, y la portada española ES la
        # raíz del sitio. El "../" de más que había aquí mandaba a todas las
        # páginas de documentación un nivel por encima de la web.
        [ "$L" = en ] && alt_href="${pre}index.html" || alt_href="${pre}en/index.html"
    fi
    cat <<HTML
<!doctype html>
<html lang="$L"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="description" content="$(t meta.desc)">
<meta property="og:title" content="$ti">
<meta property="og:description" content="$(t meta.og)">
<meta property="og:image" content="https://m1keos.duckdns.org/capturas/escritorio.png">
<meta property="og:type" content="website">
<link rel="alternate" hreflang="$otro" href="$alt_href">
<title>$ti</title>
<link rel="icon" href="${pre}favicon.svg" type="image/svg+xml">
<link rel="preload" href="${pre}tipos/geist-700.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="${pre}estilo.css">
<script>
/* El tema elegido se aplica ANTES de pintar nada.
   Si esto fuera al final del cuerpo, quien tenga elegido el tema oscuro vería
   un fogonazo blanco en cada carga: el navegador pinta con el tema por defecto
   y lo corrige después. Son cuatro líneas y van aquí por eso. */
try{var _t=localStorage.getItem("mikeos-tema");
    if(_t)document.documentElement.setAttribute("data-tema",_t);}catch(e){}
</script>
</head><body>
<nav><div class="cont">
  <a class="marca" href="${pre_idioma}index.html">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 6l6 6-6 6"/><path d="M13 18h7"/></svg>
    MIKE OS</a>
  <span class="derecha"></span>
  <a class="enl idioma" href="$alt_href" hreflang="$otro" lang="$otro">$(t nav.idioma)</a>
  <button class="tema" type="button" aria-label="$(t nav.tema)" title="$(t nav.tema)">
    <svg class="sol" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
         stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4.2"/>
      <path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.2 5.2l1.5 1.5M17.3 17.3l1.5 1.5M18.8 5.2l-1.5 1.5M6.7 17.3l-1.5 1.5"/></svg>
    <svg class="luna" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 14.5A8.5 8.5 0 019.5 4a8.5 8.5 0 1010.5 10.5z"/></svg>
  </button>
  <a class="btn $([ "$act" = descargas ] && echo aqui)" href="${pre_idioma}$([ "$L" = en ] && echo downloads.html || echo descargas.html)">$(t nav.descargar)</a>
  <button class="hamburguesa" type="button" aria-label="$(t nav.menu)" title="$(t nav.menu)"
          aria-expanded="false" aria-controls="menu-principal">
    <span></span><span></span><span></span>
  </button>
</div>
<div class="menu" id="menu-principal" hidden>
  <div class="menu-lista">
    <a class="$([ "$act" = inicio ] && echo aqui)" href="${pre_idioma}index.html">$(t nav.inicio)</a>
    <a class="$([ "$act" = capturas ] && echo aqui)" href="${pre}capturas/index.html">$(t nav.capturas)</a>
    <a class="$([ "$act" = docs ] && echo aqui)" href="${pre}docs/index.html">$(t nav.docs)</a>
    <a class="$([ "$act" = wiki ] && echo aqui)" href="${pre}wiki/index.html">$(t nav.wiki)</a>
    <a href="https://github.com/${MIKEOS_REPO_GITHUB:-M1KE-27/m1keos}">$(t nav.codigo)</a>
    <a class="solo-estrecho" href="$alt_href" hreflang="$otro" lang="$otro">$(t nav.idioma)</a>
  </div>
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
$(t pie.licencia)
$(t pie.actualizado)
<a href="https://github.com/${MIKEOS_REPO_GITHUB:-M1KE-27/m1keos}">$(t pie.codigo)</a>
</div></footer>
<script>
/* El menú. Un botón que abre y cierra un panel.
   Se usa el atributo "hidden" en vez de display:none desde JavaScript: así el
   panel sigue estando oculto de verdad para un lector de pantalla, y si el
   JavaScript no llega a ejecutarse nunca queda a medio abrir. */
(function(){
  var b=document.querySelector(".hamburguesa");
  var m=document.getElementById("menu-principal");
  if(!b||!m) return;
  function cerrar(){ m.hidden=true; b.setAttribute("aria-expanded","false"); }
  function abrir(){ m.hidden=false; b.setAttribute("aria-expanded","true"); }
  b.addEventListener("click",function(e){
    e.stopPropagation();
    if(m.hidden) abrir(); else cerrar();
  });
  /* Pulsar fuera cierra. Sin esto, en escritorio el panel se queda abierto
     tapando contenido y hay que volver al botón para quitarlo. */
  document.addEventListener("click",function(e){
    if(!m.hidden && !m.contains(e.target)) cerrar();
  });
  /* Y Escape, que es lo que prueba cualquiera que no use ratón. */
  document.addEventListener("keydown",function(e){
    if(e.key==="Escape" && !m.hidden){ cerrar(); b.focus(); }
  });
})();

/* El botón de tema. Tres estados y no dos: claro, oscuro, y "lo que diga el
   sistema", que es donde empieza todo el mundo. Sin el tercero, quien tenga el
   móvil en automático pierde ese automático en cuanto toca el botón una vez y
   no hay forma de recuperarlo. */
(function(){
  var b=document.querySelector(".tema"); if(!b) return;
  var r=document.documentElement;
  function sistemaOscuro(){
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }
  b.addEventListener("click",function(){
    var actual=r.getAttribute("data-tema");
    var oscuroAhora = actual ? actual==="oscuro" : sistemaOscuro();
    var nuevo = oscuroAhora ? "claro" : "oscuro";
    /* Si lo elegido vuelve a coincidir con lo que dice el sistema, se borra la
       preferencia en vez de guardarla: así el sitio vuelve a seguir al sistema
       cuando este cambie solo de día a noche. */
    if((nuevo==="oscuro")===sistemaOscuro()){
      r.removeAttribute("data-tema");
      try{localStorage.removeItem("mikeos-tema");}catch(e){}
    }else{
      r.setAttribute("data-tema",nuevo);
      try{localStorage.setItem("mikeos-tema",nuevo);}catch(e){}
    }
  });
})();
</script>
</body></html>
HTML
}

# La cabecera y el pie, volcados a un archivo para que los generadores escritos
# en Python (documentación y wiki) usen EXACTAMENTE los mismos. Antes cada uno
# llevaba su propia copia del HTML de la navegación, y al tocar una el resto se
# quedaba atrás: el índice de documentación seguía enseñando un menú de hace dos
# versiones. Un solo sitio, y se acabó.
#
# La documentación se sirve en inglés, que es como está escrita, así que sus
# cabeceras se generan con ese idioma.
L=en
for _sec in inicio capturas docs wiki descargas; do
    cabecera "@TITULO@" "$_sec" "@PRE@" > "$WEB/.cabecera-$_sec.html"
done
pie > "$WEB/.pie.html"
L=es

# El icono, como SVG: son 200 bytes y la marca del sistema es exactamente esto.
cat > "$WEB/favicon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
     stroke="#00d4ff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
<rect width="24" height="24" rx="5" fill="#090b10" stroke="none"/>
<path d="M5 6l6 6-6 6"/><path d="M13 18h7"/></svg>
SVG

# --- Página de inicio ---------------------------------------------------------
paso "Escribiendo la portada"

# La portada, en el idioma que se le pida.
#
# Las dos versiones viven en la misma función y una al lado de la otra, sección
# por sección. Con un archivo por idioma, tocar la española y olvidar la inglesa
# no produce ningún error: produce una web que dice dos cosas distintas según
# quién la mire, y nadie se entera hasta que alguien se queja.
portada() {  # portada <es|en>
    L="$1"
    local pre alt dest
    if [ "$L" = en ]; then pre="../"; alt="../index.html"; else pre=""; alt="en/index.html"; fi
    ALTERNA="$alt"
    cabecera "MIKE OS" inicio "$pre" suelto

    # --- Portada -------------------------------------------------------------
    if [ "$L" = en ]; then
    cat <<HTML
<div class="portada"><div class="cont">
  <div>
    <p class="chapa"><span class="punto"></span><b>$VERSION</b><span class="sep">/</span>alpha</p>
    <h1>Written from the kernel up.</h1>
    <p class="entradilla">MIKE OS is a complete operating system. Its own kernel
      build, no systemd, and a package manager, shell and desktop written for it.</p>
    <div class="acciones">
      <a class="btn btn-vivo" href="$URL_ISO">Download $ETIQUETA_ISO <span class="peso">$ISO_TAM</span></a>
      <a class="btn" href="${pre}docs/instalacion.html">How to install it</a>
    </div>
    <p class="bajo-boton">x86_64 &nbsp;·&nbsp; UEFI only &nbsp;·&nbsp; Secure Boot off</p>
  </div>
  <div class="captura-portada">
    <img src="${pre}capturas/bienvenida.png" $(dim capturas/bienvenida.png)
         alt="The MIKE OS desktop with the welcome window open">
  </div>

<div class="cifras">
  <div class="cifra"><b>0.59 s</b><span>from kernel to console</span></div>
  <div class="cifra"><b>324 MB</b><span>of RAM with the desktop running</span></div>
  <div class="cifra"><b>25 s</b><span>to build the system</span></div>
  <div class="cifra"><b>0</b><span>lines of systemd</span></div>
</div>
</div></div>

<div class="cont">

<section>
  <p class="rotulo">New in $VERSION</p>
  <div class="prosa">
    <h2>Power, drivers and the things that were quietly broken</h2>
    <p>Most of this release is not new features: it is hardware that said it
      worked and did not. Each item below is a real failure that left no error
      message behind — which is why they lasted so long.</p>
  </div>
  <div class="nuevo">
    <div><span class="marca-nueva">new</span><b>Power profiles</b>
      <p>Maximum, balanced, saving, or automatic. On a desktop, automatic
        already means maximum: nothing sleeps and the CPU never steps down.
        On a laptop you also choose what closing the lid does — and suspend is
        only offered if your machine actually advertises it.</p></div>
    <div><span class="marca-nueva">new</span><b>Hardware panel</b>
      <p>Scans graphics, wired and USB networking, Bluetooth, sound, input,
        camera, disks, CPU and battery, and says which of four states each one
        is in: working, no driver, missing firmware, or detected but stopped.
        Four different faults that used to look identical.</p></div>
    <div><b>Bluetooth</b>
      <p>The firmware was there all along. <code>btusb</code> binds to the
        adapter <em>before</em> asking for it, so from <code>/sys</code> a dead
        adapter was indistinguishable from a healthy one. It is now rescued by
        rebinding the driver once the real filesystem is mounted.</p></div>
    <div><b>Games and Java</b>
      <p>XWayland was dying at startup because <code>xkbcomp</code> was not in
        the image, so it could not compile its keymap — but <code>DISPLAY</code>
        stayed set, so anything using X11 failed much later talking about
        OpenGL. Minecraft was the visible casualty.</p></div>
    <div><b>Updates that do not break sudo</b>
      <p>The core package shipped <code>m-sudo</code> without its setuid bit.
        The first <code>mpm upgrade</code> on any installed system would have
        left you unable to become root or unlock the screen — and fixing it
        needed the very sudo it had just broken.</p></div>
    <div><b>Copying files in</b>
      <p><code>scp</code> to a MIKE OS machine failed, because
        <code>sftp-server</code> was missing and the error named a path without
        saying a program was absent. It ships now.</p></div>
  </div>
</section>

<section>
  <div class="prosa">
    <h2>What is in here</h2>
    <p>MIKE OS is not a distribution with a new theme on top. The kernel is
      configured and compiled here, the init is runit, and the package manager,
      the shell, the terminal and the desktop are written for this system.</p>
  </div>
  <div class="piezas">
    <div><b>kernel $KVER</b><span>configured by hand, with its own UEFI boot path and btrfs built in</span></div>
    <div><b>runit</b><span>the init. Starts services and watches them; if one dies, it comes back</span></div>
    <div><b>mpm</b><span>package manager with a snapshot before every change, and rollback</span></div>
    <div><b>mkshell</b><span>the system shell</span></div>
    <div><b>Hyprland + Quickshell</b><span>the compositor, and a bar written in QML for this system</span></div>
    <div><b>$N_PKG packages</b><span>in its own repository</span></div>
  </div>
</section>

<section>
  <div class="prosa">
    <h2>It installs from a interface, not from the terminal</h2>
    <p>Up to the previous version you had to know that a command called
      <code>m-install</code> existed. There is now a graphical installer: it
      finds the disk on its own, shows you what is on it, and tells you what you
      are about to erase before erasing it.</p>
  </div>

  <figure>
    <img src="${pre}capturas/instalador-disco.png" $(dim capturas/instalador-disco.png)
         alt="The installer showing the disk, its partitions and the warning about what will be erased">
    <figcaption>It detects the disk, lists its partitions with whatever system is
      on each one, and warns in amber about what will be lost. If something would
      stop the machine booting afterwards, it refuses to continue and says why.</figcaption>
  </figure>

  <div class="prosa">
    <h3>Installing alongside Windows</h3>
    <p>It uses the free space and touches nothing that is already there. Any EFI
      partition it finds is kept exactly as it is, with the Windows boot loader
      inside: that is what makes Windows keep appearing in the menu instead of
      "disappearing". GRUB adds it on its own when the install finishes.</p>

    <h3>Someone can help you from their own house</h3>
    <p>If you get stuck installing, the network step turns on SSH, creates a
      temporary four-letter account and shows you the exact command and password
      to read out over the phone. Turning it off deletes the account.</p>
  </div>

  <figure>
    <img src="${pre}capturas/instalador-red.png" $(dim capturas/instalador-red.png)
         alt="The installer's network step, with the remote help card">
    <figcaption>English by default, Spanish one click away.</figcaption>
  </figure>
</section>

<section>
  <div class="prosa">
    <h2>Writing it and booting</h2>
  </div>
  <ol class="pasos">
    <li>
      <h3>Write the image to a USB stick</h3>
      <p>Check the device letter before you run this: it erases the whole stick.</p>
      <pre><code>sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync</code></pre>
    </li>
    <li>
      <h3>Turn off Secure Boot</h3>
      <p>The kernel does not carry Microsoft's signature, so the firmware refuses
        to run it with Secure Boot on. On most machines you turn it off in the
        board's setup screen at power-on.</p>
    </li>
    <li>
      <h3>Try it, then install it if you like it</h3>
      <p>The stick boots to a complete desktop running in memory: it does not
        touch your disk. When you want to install it, the button is in the
        welcome window.</p>
    </li>
  </ol>
</section>

<section>
  <div class="prosa">
    <h2>What does not work yet</h2>
    <p>This is an alpha, and this list is part of the documentation, not a
      footnote. If something here would block you, better to know now than with
      the disk half formatted.</p>
  </div>
  <div class="limites">
    <div><b>Secure Boot</b><p>It has to be turned off. The kernel is not signed by Microsoft and will not be any time soon.</p></div>
    <div><b>UEFI only</b><p>It does not boot via BIOS or CSM. On machines older than 2012 it will not work.</p></div>
    <div><b>Manual partitioning</b><p>The installer can erase, install alongside and replace. To create or resize by hand it brings GParted with <code>mpm install gparted</code>.</p></div>
    <div><b>Privileges</b><p><code>m-sudo</code> gives the account root without asking for a password. The lock screen protects against passers-by, not against someone with time and a keyboard.</p></div>
    <div><b>Real hardware</b><p>Tested on QEMU with real UEFI firmware, and on a Surface Laptop 4. On other physical laptops it is still untested: that is what this release is for.</p></div>
  </div>
</section>

<section>
  <div class="prosa"><h2>The desktop</h2>
  <p>The bar and the Control Centre are written in QML for this system. The bar
    can go on any edge, change shape, and carry whichever modules you want. The
    wallpaper can tint the whole palette, terminal included.</p>
  </div>
  <div class="galeria">
    <a href="${pre}capturas/centro-de-control.png"><img $(dim capturas/centro-de-control.png) src="${pre}capturas/centro-de-control.png" alt="The MIKE OS Control Centre" loading="lazy"><span>The Control Centre</span></a>
    <a href="${pre}capturas/bloqueo.png"><img $(dim capturas/bloqueo.png) src="${pre}capturas/bloqueo.png" alt="The lock screen" loading="lazy"><span>The lock screen</span></a>
    <a href="${pre}capturas/terminal.png"><img $(dim capturas/terminal.png) src="${pre}capturas/terminal.png" alt="The MIKE OS terminal" loading="lazy"><span>The terminal</span></a>
    <a href="${pre}capturas/grub.png"><img $(dim capturas/grub.png) src="${pre}capturas/grub.png" alt="The MIKE OS boot menu" loading="lazy"><span>The boot menu</span></a>
  </div>
  <p style="margin-top:22px"><a href="${pre}capturas/index.html">See every screenshot</a></p>
</section>

</div>
HTML
    else
    cat <<HTML
<div class="portada"><div class="cont">
  <div>
    <p class="chapa"><span class="punto"></span><b>$VERSION</b><span class="sep">/</span>alpha</p>
    <h1>Escrito desde el kernel hacia arriba.</h1>
    <p class="entradilla">MIKE OS es un sistema operativo completo. Kernel
      propio, sin systemd, gestor de paquetes y escritorio escritos para él.</p>
    <div class="acciones">
      <a class="btn btn-vivo" href="$URL_ISO">Descargar $ETIQUETA_ISO <span class="peso">$ISO_TAM</span></a>
      <a class="btn" href="${pre}docs/instalacion.html">Cómo se instala</a>
    </div>
    <p class="bajo-boton">x86_64 &nbsp;·&nbsp; sólo UEFI &nbsp;·&nbsp; sin Secure Boot</p>
  </div>
  <div class="captura-portada">
    <img src="${pre}capturas/bienvenida.png" $(dim capturas/bienvenida.png)
         alt="El escritorio de MIKE OS con la ventana de bienvenida abierta">
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
  <p class="rotulo">Novedades de la $VERSION</p>
  <div class="prosa">
    <h2>Energía, controladores, y lo que estaba roto sin decirlo</h2>
    <p>Casi nada de esta versión son funciones nuevas: es hardware que decía
      funcionar y no funcionaba. Cada cosa de aquí abajo es una avería real que
      no dejaba ni un mensaje de error, que es justo por lo que duraron tanto.</p>
  </div>
  <div class="nuevo">
    <div><span class="marca-nueva">nuevo</span><b>Perfiles de energía</b>
      <p>Máximo, equilibrado, ahorro o automático. En un sobremesa, automático
        ya significa máximo: nada se duerme y el procesador no baja de
        frecuencia. En un portátil eliges además qué hace al cerrar la tapa, y
        suspender sólo se ofrece si tu equipo lo admite de verdad.</p></div>
    <div><span class="marca-nueva">nuevo</span><b>Apartado de controladores</b>
      <p>Analiza gráfica, red por cable y por USB, Bluetooth, sonido, entrada,
        cámara, discos, procesador y batería, y dice en cuál de cuatro estados
        está cada cosa: funciona, sin driver, le falta firmware, o detectado
        pero parado. Cuatro averías distintas que antes se veían igual.</p></div>
    <div><b>Bluetooth</b>
      <p>El firmware estaba desde el principio. <code>btusb</code> se engancha
        al adaptador <em>antes</em> de pedirlo, así que desde <code>/sys</code>
        un adaptador muerto era indistinguible de uno sano. Ahora se rescata
        reenganchando el driver cuando el sistema de archivos ya está montado.</p></div>
    <div><b>Juegos y Java</b>
      <p>XWayland se moría al arrancar porque <code>xkbcomp</code> no estaba en
        la imagen y no podía compilar su mapa de teclado — pero
        <code>DISPLAY</code> seguía puesto, así que cualquier programa de X11
        fallaba muchísimo después hablando de OpenGL. Minecraft era la víctima
        visible.</p></div>
    <div><b>Actualizar sin perder sudo</b>
      <p>El paquete del núcleo metía <code>m-sudo</code> sin su bit setuid. La
        primera <code>mpm upgrade</code> de cualquier sistema instalado te
        habría dejado sin poder ser root y sin poder desbloquear la pantalla, y
        arreglarlo necesitaba justo el sudo que se acababa de romper.</p></div>
    <div><b>Copiar archivos al equipo</b>
      <p><code>scp</code> hacia una máquina MIKE OS fallaba porque faltaba
        <code>sftp-server</code>, y el error nombraba una ruta sin decir que lo
        que faltaba era un programa. Ahora va dentro.</p></div>
  </div>
</section>

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
    <img src="${pre}capturas/instalador-disco.png" $(dim capturas/instalador-disco.png)
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
    <img src="${pre}capturas/instalador-red.png" $(dim capturas/instalador-red.png)
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
    <div><b>Hardware real</b><p>Probado en QEMU con firmware UEFI de verdad y en una Surface Laptop 4. En otros portátiles físicos sigue sin probar: esta versión existe para eso.</p></div>
  </div>
</section>

<section>
  <div class="prosa"><h2>El escritorio</h2>
  <p>La barra y el Centro de Control están escritos en QML para este sistema. Se
    puede mover la barra a cualquier borde, cambiar su forma y elegir qué módulos
    lleva. El fondo de pantalla puede teñir la paleta entera, terminal incluida.</p>
  </div>
  <div class="galeria">
    <a href="${pre}capturas/centro-de-control.png"><img $(dim capturas/centro-de-control.png) src="${pre}capturas/centro-de-control.png" alt="El Centro de Control de MIKE OS" loading="lazy"><span>El Centro de Control</span></a>
    <a href="${pre}capturas/bloqueo.png"><img $(dim capturas/bloqueo.png) src="${pre}capturas/bloqueo.png" alt="La pantalla de bloqueo" loading="lazy"><span>La pantalla de bloqueo</span></a>
    <a href="${pre}capturas/terminal.png"><img $(dim capturas/terminal.png) src="${pre}capturas/terminal.png" alt="La terminal de MIKE OS" loading="lazy"><span>La terminal</span></a>
    <a href="${pre}capturas/grub.png"><img $(dim capturas/grub.png) src="${pre}capturas/grub.png" alt="El menú de arranque de MIKE OS" loading="lazy"><span>El menú de arranque</span></a>
  </div>
  <p style="margin-top:22px"><a href="${pre}capturas/index.html">Ver todas las capturas</a></p>
</section>

</div>
HTML
    fi
    pie suelto
}

mkdir -p "$WEB/en"
portada es > "$WEB/index.html"
portada en > "$WEB/en/index.html"
L=es

# --- Descargas ----------------------------------------------------------------
paso "Descargas"

descargas() {  # descargas <es|en>
    L="$1"
    local pre alt
    if [ "$L" = en ]; then pre="../"; alt="../descargas.html"; else pre=""; alt="en/downloads.html"; fi
    ALTERNA="$alt"
    if [ "$L" = en ]; then
        cabecera "Download · MIKE OS" descargas "$pre"
    else
        cabecera "Descargar · MIKE OS" descargas "$pre"
    fi

    if [ "$HAY_ISO" -ne 1 ]; then
        if [ "$L" = en ]; then
            printf '%s\n' '<header><h1>Download</h1></header>' \
                '<div class="aviso"><p>No image has been published yet.</p></div>'
        else
            printf '%s\n' '<header><h1>Descargar</h1></header>' \
                '<div class="aviso"><p>Todavía no hay ninguna imagen publicada.</p></div>'
        fi
        pie
        return
    fi

    if [ "$L" = en ]; then
    cat <<HTML
<header><h1>Download</h1>
<p class="lema">One image that boots on any UEFI machine. You can try the whole
  system without installing anything.</p></header>

<table>
  <tr><th>File</th><th>Size</th><th>Kernel</th></tr>
  <tr><td>mikeos.iso</td><td>$ISO_TAM</td><td>$KVER</td></tr>
</table>
<p class="tenue">SHA256:<br><code style="font-size:11px;word-break:break-all">$ISO_SHA</code></p>
<p style="margin:22px 0 8px"><a class="btn btn-vivo" href="$URL_ISO">Download mikeos.iso <span class="peso">$ISO_TAM</span></a></p>
<p class="tenue">GitHub serves the download and it starts on click, with no
interstitial page. It works that way because this site lives on a mini PC at
home: its uplink gives about 780 KB/s, which is nearly four minutes per download
and one at a time. Packages, which are small, do come from here.</p>

<h2>Writing it to a USB stick</h2>
<pre><span class="c"># first check that what you downloaded is what was published</span>
sha256sum mikeos.iso

<span class="c"># /dev/sdX is your stick. It will be erased completely.</span>
sudo dd if=mikeos.iso of=/dev/sdX bs=4M status=progress oflag=sync</pre>

<div class="aviso"><p><strong>Secure Boot.</strong> You have to turn it off in
  the UEFI before booting the stick. This kernel does not carry Microsoft's
  signature, so with Secure Boot on the firmware refuses to run it. On a Surface
  you turn it off by entering the UEFI (hold volume up while powering on).</p></div>

<h2>Trying it without installing</h2>
<p>The image boots into memory: you can look around, touch everything and shut
  down without your disk noticing. When you want to install it, the button is in
  the welcome window.</p>
<p><a href="${pre}docs/instalacion.html">Full installation guide</a></p>
HTML
    else
    cat <<HTML
<header><h1>Descargar</h1>
<p class="lema">Una imagen que arranca en cualquier equipo con UEFI. Puedes
  probar el sistema sin instalar nada.</p></header>

<table>
  <tr><th>Archivo</th><th>Tamaño</th><th>Kernel</th></tr>
  <tr><td>mikeos.iso</td><td>$ISO_TAM</td><td>$KVER</td></tr>
</table>
<p class="tenue">SHA256:<br><code style="font-size:11px;word-break:break-all">$ISO_SHA</code></p>
<p style="margin:22px 0 8px"><a class="btn btn-vivo" href="$URL_ISO">Descargar mikeos.iso <span class="peso">$ISO_TAM</span></a></p>
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
<p><a href="${pre}docs/instalacion.html">Guía de instalación completa</a></p>
HTML
    fi
    pie
}

descargas es > "$WEB/descargas.html"
descargas en > "$WEB/en/downloads.html"
L=es

verde "  index.html y descargas.html, en español y en inglés"

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
    # Las páginas en inglés también. Se quedaron fuera de esta lista el día
    # que se añadieron, así que podían no haberse subido y la comprobación
    # habría dicho que todo estaba bien.
    _fallos=0
    for ruta in "" "descargas.html" "docs/index.html" "wiki/index.html" \
                "capturas/index.html" "en/index.html" "en/downloads.html" \
                "estilo.css"; do
        cod="$(curl -fsS --max-time 15 -o /dev/null -w '%{http_code}' "https://m1keos.duckdns.org/$ruta" 2>/dev/null || echo ---)"
        printf '    %-24s %s\n' "/$ruta" "$cod"
        [ "$cod" = "200" ] || _fallos=$((_fallos + 1))
    done
    if [ "$_fallos" -gt 0 ]; then
        # Y si algo no responde, se dice y se sale con error. Antes se
        # imprimía el código y se terminaba en verde igual: un 404 pasaba
        # desapercibido entre los 200 de al lado.
        err "$_fallos de las páginas comprobadas no responden."
        exit 1
    fi
fi
