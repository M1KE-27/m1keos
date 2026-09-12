#!/usr/bin/env python3
"""Genera el fondo de pantalla de MIKE OS.

Existe como script y no como PNG suelto por el mismo motivo que el resto del
sistema se compila en vez de descargarse: si mañana cambia el acento de la
paleta, el fondo se regenera en un segundo en lugar de quedarse desfasado con
un color que ya no usa nadie. Y se puede leer qué es cada cosa.

El fondo anterior era un degradado casi negro: sobre el escritorio no se
distinguía de "no hay fondo", y daba la sensación de que el sistema no había
terminado de arrancar.

    ./scripts/fondo.py                 -> build/desktop/wallpaper.png
    ./scripts/fondo.py salida.png
"""
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ANCHO, ALTO = 1920, 1080

# Los mismos colores que build/desktop/theme/colors.conf. Si cambian allí,
# cambian aquí: es un fondo de MIKE OS, no un fondo cualquiera.
ACENTO = (0, 212, 255)
ACENTO_2 = (0, 136, 255)
FONDO = (9, 11, 16)


def mezclar(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sumar(fondo, capa):
    """Suma dos imágenes recortando a 255. Es lo que hace el modo "screen" de
    un editor: los resplandores se acumulan sin apagar lo que hay debajo."""
    return Image.fromarray(np.clip(
        np.asarray(fondo, dtype="int16") + np.asarray(capa, dtype="int16"),
        0, 255).astype("uint8"))


def base():
    """Degradado diagonal: más claro arriba a la derecha, donde luego va el
    resplandor, y más oscuro abajo a la izquierda, que es donde se apoyan los
    iconos y el texto de las ventanas."""
    im = Image.new("RGB", (ANCHO, ALTO))
    px = im.load()
    claro = (16, 22, 34)
    for y in range(ALTO):
        for x in range(0, ANCHO, 4):
            t = (x / ANCHO * 0.62 + (1 - y / ALTO) * 0.38)
            c = mezclar(FONDO, claro, t ** 1.6)
            for dx in range(4):
                if x + dx < ANCHO:
                    px[x + dx, y] = c
    return im


def resplandor(im):
    """Foco suave en el acento. Se dibuja pequeño y se desenfoca mucho: sale
    más limpio que pintar el degradado a mano y no deja bandas."""
    capa = Image.new("RGB", (ANCHO // 4, ALTO // 4), (0, 0, 0))
    d = ImageDraw.Draw(capa)
    cx, cy = int(ANCHO * 0.70) // 4, int(ALTO * 0.28) // 4
    for r, f in ((150, 0.10), (100, 0.16), (60, 0.22), (30, 0.30)):
        c = tuple(int(v * f) for v in mezclar(ACENTO_2, ACENTO, 0.5))
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c)
    capa = capa.filter(ImageFilter.GaussianBlur(28)).resize((ANCHO, ALTO), Image.BICUBIC)
    return sumar(im, capa)


def rejilla(im):
    """Retícula muy tenue. No se ve de frente; se nota si falta, porque sin
    ella el degradado queda plano como un fondo de plantilla."""
    capa = Image.new("RGB", (ANCHO, ALTO), (0, 0, 0))
    d = ImageDraw.Draw(capa)
    paso = 60
    for x in range(0, ANCHO, paso):
        d.line((x, 0, x, ALTO), fill=(6, 9, 13))
    for y in range(0, ALTO, paso):
        d.line((0, y, ANCHO, y), fill=(6, 9, 13))
    return sumar(im, capa)


def marca(im):
    """El prompt >_ , la misma marca que lleva la barra (Icono.qml, "logo").
    Grande y muy tenue: se reconoce sin competir con las ventanas."""
    capa = Image.new("RGB", (ANCHO, ALTO), (0, 0, 0))
    d = ImageDraw.Draw(capa)

    # Mismas proporciones que el icono de 24x24: (5,6)->(11,12)->(5,18) y la
    # línea de (13,18) a (20,18).
    esc = 26
    # La marca ocupa de x=5 a x=20 y de y=6 a y=18 en la rejilla del icono:
    # se centra por su punto medio real, no por su altura.
    ox = ANCHO / 2 - 12.5 * esc
    oy = ALTO / 2 - 12.0 * esc

    def p(x, y):
        return (ox + x * esc, oy + y * esc)

    grosor = int(esc * 0.72)
    trazo = tuple(int(v * 0.30) for v in ACENTO)
    d.line([p(5, 6), p(11, 12), p(5, 18)], fill=trazo, width=grosor, joint="curve")
    d.line([p(13, 18), p(20, 18)], fill=trazo, width=grosor)

    halo = capa.filter(ImageFilter.GaussianBlur(38))
    fundido = Image.fromarray(np.clip(
        np.asarray(capa, dtype="int16") * 0.55
        + np.asarray(halo, dtype="int16") * 0.9, 0, 255).astype("uint8"))
    return sumar(im, fundido)


def vineta(im):
    """Oscurece los bordes. Centra la mirada y, de paso, hace que la barra
    -- que va pegada a un borde -- se recorte mejor contra el fondo."""
    yy, xx = np.mgrid[0:ALTO, 0:ANCHO]
    dx = (xx - ANCHO / 2) / (ANCHO / 2)
    dy = (yy - ALTO / 2) / (ALTO / 2)
    r = np.sqrt(dx ** 2 + dy ** 2) / math.sqrt(2)
    factor = np.clip(1.0 - (r ** 2.2) * 0.55, 0, 1)[:, :, None]
    return Image.fromarray((np.asarray(im, dtype="float32") * factor).astype("uint8"))


def main():
    destino = sys.argv[1] if len(sys.argv) > 1 else "build/desktop/wallpaper.png"
    im = base()
    im = resplandor(im)
    im = rejilla(im)
    im = marca(im)
    im = vineta(im)
    im.save(destino, optimize=True)
    print(f"fondo escrito en {destino}")


main()
