#!/usr/bin/env python3
"""Genera el tema de cursor de MIKE OS: negro, con borde claro.

Por qué existe
--------------
La imagen no traía NI UN tema de cursor -- /usr/share/icons no existía
siquiera -- y encima start-mike-desktop exportaba XCURSOR_THEME="" (la cadena
vacía, que es peor que no ponerlo: pisa cualquier valor por defecto con un
nombre que no existe). Así que el cursor era el que decidiera cada aplicación
por su cuenta, sin ninguna coherencia.

Cómo lo hace
------------
No dibuja las formas desde cero: parte de un tema existente y le invierte el
color, conservando la silueta, los tamaños y -- lo más importante -- los
puntos de agarre de cada cursor, que son los que deciden dónde pulsa
exactamente. Reinventar sesenta y tres formas a mano saldría peor y tardaría
un mes.

El resultado es negro con borde claro: se ve sobre un fondo blanco (por el
relleno) y sobre uno negro (por el borde), que es lo que se pedía.

El formato XCursor
------------------
Es sencillo y está documentado. Un archivo son:

    "Xcur" | tamaño de cabecera | versión | nº de entradas
    y por cada entrada: tipo | subtipo | posición en el archivo

y cada imagen, en su posición:

    cabecera | tipo | subtipo(=tamaño nominal) | versión
    ancho | alto | x del agarre | y del agarre | retardo
    y después ancho*alto píxeles ARGB de 32 bits, con el alfa ya multiplicado.

Sólo se tocan los píxeles; las cabeceras se copian tal cual.
"""
import os
import struct
import sys

MAGICO = b"Xcur"
TIPO_IMAGEN = 0xFFFD0002


def recolorear(datos):
    """Invierte el brillo de una imagen ARGB conservando la transparencia."""
    salida = bytearray(datos)
    for i in range(0, len(salida), 4):
        b, g, r, a = salida[i], salida[i + 1], salida[i + 2], salida[i + 3]
        if a == 0:
            continue
        # El alfa viene multiplicado en el color: hay que deshacerlo antes de
        # tocar nada, o las zonas semitransparentes salen con el brillo mal.
        rr = min(255, r * 255 // a)
        gg = min(255, g * 255 // a)
        bb = min(255, b * 255 // a)
        # Un gris por brillo percibido, e invertido: lo blanco se vuelve negro
        # y el borde oscuro se vuelve claro.
        luz = (rr * 299 + gg * 587 + bb * 114) // 1000
        nuevo = 255 - luz
        # Un pelín de contraste extra: el relleno bien negro y el borde bien
        # claro, que es lo que hace que se vea sobre cualquier fondo.
        if nuevo < 110:
            nuevo = max(0, nuevo - 30)
        elif nuevo > 150:
            nuevo = min(255, nuevo + 35)
        v = nuevo * a // 255          # volver a multiplicar por el alfa
        salida[i] = salida[i + 1] = salida[i + 2] = v
    return bytes(salida)


def convertir(origen, destino):
    with open(origen, "rb") as f:
        datos = bytearray(f.read())

    if bytes(datos[0:4]) != MAGICO:
        return False

    tam_cab, _version, n = struct.unpack_from("<III", datos, 4)
    for i in range(n):
        base = tam_cab + i * 12
        tipo, _sub, pos = struct.unpack_from("<III", datos, base)
        if tipo != TIPO_IMAGEN:
            continue
        # Cabecera de la imagen: tamaño, tipo, subtipo, versión, ancho, alto,
        # agarre x, agarre y, retardo. Nueve enteros de 32 bits.
        ch_tam, = struct.unpack_from("<I", datos, pos)
        ancho, alto = struct.unpack_from("<II", datos, pos + 16)
        ini = pos + ch_tam
        fin = ini + ancho * alto * 4
        datos[ini:fin] = recolorear(bytes(datos[ini:fin]))

    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with open(destino, "wb") as f:
        f.write(bytes(datos))
    return True


def main():
    if len(sys.argv) < 3:
        print("Uso: generar-cursor.py <tema-origen> <directorio-destino>", file=sys.stderr)
        return 1
    origen, destino = sys.argv[1], sys.argv[2]
    dir_cursores = os.path.join(origen, "cursors")
    if not os.path.isdir(dir_cursores):
        print(f"no hay cursores en {dir_cursores}", file=sys.stderr)
        return 1

    salida = os.path.join(destino, "cursors")
    os.makedirs(salida, exist_ok=True)

    hechos = enlaces = 0
    # Primero los archivos de verdad, después los alias: un enlace a un archivo
    # que todavía no existe es un enlace roto.
    for nombre in sorted(os.listdir(dir_cursores)):
        ruta = os.path.join(dir_cursores, nombre)
        if os.path.islink(ruta) or not os.path.isfile(ruta):
            continue
        if convertir(ruta, os.path.join(salida, nombre)):
            hechos += 1

    for nombre in sorted(os.listdir(dir_cursores)):
        ruta = os.path.join(dir_cursores, nombre)
        if not os.path.islink(ruta):
            continue
        apunta = os.readlink(ruta)
        enlace = os.path.join(salida, nombre)
        if os.path.lexists(enlace):
            os.remove(enlace)
        os.symlink(apunta, enlace)
        enlaces += 1

    with open(os.path.join(destino, "index.theme"), "w", encoding="utf-8") as f:
        f.write("[Icon Theme]\n"
                "Name=MikeOS-Cursor\n"
                "Comment=Cursor de MIKE OS: negro con borde claro\n"
                "Inherits=Adwaita\n")

    print(f"  -> cursor MikeOS-Cursor: {hechos} formas y {enlaces} alias.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
