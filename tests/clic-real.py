#!/usr/bin/env python3
"""Pulsa como un dedo en un touchpad: moviéndose un poco mientras pulsa.

Por qué existe
--------------
tests/clic.py salta a una coordenada, pulsa y suelta SIN MOVERSE NI UN PÍXEL.
Ningún dedo hace eso.

La diferencia no es un detalle. En QtQuick, un TapHandler con la política por
defecto (DragThreshold) CANCELA el toque si el puntero se mueve unos píxeles
entre pulsar y soltar. Como el banco de pruebas nunca se movía, daba por buenos
botones que en un portátil de verdad no respondían: ésa es toda la historia de
"todo muy bonito en QEMU y en hardware real nada".

Esto usa el mismo puntero absoluto que clic.py -- así no hay que pelearse con
la aceleración del ratón, que hace que un movimiento relativo de 1896 unidades
no acabe en x=1896 -- pero DESPLAZA el puntero unos píxeles mientras el botón
está pulsado. Eso es lo que estaba sin probar.

    ./tests/clic-real.py 1690 23            pulsa ahí, con 8 px de arrastre
    ./tests/clic-real.py 1690 23 --quieto   pulsa sin moverse (para comparar)
"""
import json
import os
import socket
import sys
import time

# Se respeta MIKEOS_QMP_SOCKET, como el resto del banco de pruebas. Tenerlo
# clavado aquí hacía que, cuando una prueba arrancaba su propia máquina con
# otro socket, los clics se fueran a un socket viejo o a ninguno -- y como los
# errores iban a /dev/null, la prueba decía tranquilamente que había pulsado.
SOCK = os.environ.get("MIKEOS_QMP_SOCKET", "/tmp/mikeos-qmp.sock")
ANCHO, ALTO = 1920, 1080
# El umbral de arrastre de Qt (QStyleHints::startDragDistance) son 10 píxeles
# por defecto. Con 8 no se superaba, y entonces esta prueba NO distinguía un
# control bien configurado de uno mal: lo comprobé quitando el gesturePolicy de
# una máquina en marcha y el panel seguía abriéndose igual.
#
# Con 16 sí se supera, y sigue siendo bastante menos de lo que se desvía un
# dedo al pulsar en un touchpad. Y al ser menos que el tamaño de cualquier
# botón, un control bien configurado (ReleaseWithinBounds) lo acepta sin
# problema: se suelta dentro.
ARRASTRE = 16


def qmp(s, orden):
    s.sendall((json.dumps(orden) + "\n").encode())
    time.sleep(0.15)
    try:
        return s.recv(65536).decode()
    except Exception:
        return ""


def mover_a(s, x, y):
    """El puntero absoluto usa un rango de 0..32767 en cada eje."""
    qmp(s, {"execute": "input-send-event", "arguments": {"events": [
        {"type": "abs", "data": {"axis": "x",
                                 "value": int(x * 32767 / ANCHO)}},
        {"type": "abs", "data": {"axis": "y",
                                 "value": int(y * 32767 / ALTO)}},
    ]}})


def boton(s, pulsado):
    qmp(s, {"execute": "input-send-event", "arguments": {"events": [
        {"type": "btn", "data": {"down": pulsado, "button": "left"}},
    ]}})


def main():
    global ANCHO, ALTO
    x, y = int(sys.argv[1]), int(sys.argv[2])
    quieto = "--quieto" in sys.argv
    for i, a in enumerate(sys.argv):
        if a == "--pantalla" and i + 2 < len(sys.argv):
            ANCHO, ALTO = int(sys.argv[i + 1]), int(sys.argv[i + 2])

    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    s.settimeout(2)
    s.recv(65536)
    qmp(s, {"execute": "qmp_capabilities"})

    mover_a(s, x, y)
    time.sleep(0.3)
    boton(s, True)
    if not quieto:
        # El desplazamiento que delata a los controles mal configurados.
        for paso in range(1, 4):
            time.sleep(0.04)
            desvio = ARRASTRE * paso // 3
            mover_a(s, x + desvio, y + desvio)
    time.sleep(0.12)
    boton(s, False)
    time.sleep(0.3)


if __name__ == "__main__":
    main()
