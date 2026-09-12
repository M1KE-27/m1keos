#!/usr/bin/env python3
"""Habla con la consola serie de la máquina virtual.

Existe porque hay fallos que sólo se ven desde dentro y que impiden justo lo
que haría falta para entrar: si el escritorio no arranca y SSH tampoco, la
consola serie es lo único que queda. Sin esto sólo se puede mirar el registro
y adivinar.

    ./tests/consola.py "mount | grep dev"
    ./tests/consola.py --leer            # sólo mirar lo que haya salido
"""
import socket
import sys
import time

SOCK = "/tmp/mikeos-iso-vivo/serie.sock"


def conectar():
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    s.settimeout(1.5)
    return s


def vaciar(s):
    """Se descarta lo que hubiera pendiente, para que la respuesta a la orden
    no venga mezclada con el arranque."""
    try:
        while s.recv(65536):
            pass
    except Exception:
        pass


def leer(s, segundos=3.0):
    fin = time.time() + segundos
    salida = b""
    while time.time() < fin:
        try:
            trozo = s.recv(65536)
            if not trozo:
                break
            salida += trozo
        except Exception:
            pass
    return salida.decode(errors="replace")


def main():
    s = conectar()
    if "--leer" in sys.argv:
        print(leer(s, 3))
        return

    orden = sys.argv[1] if len(sys.argv) > 1 else ""
    vaciar(s)
    # Un Enter primero: si hay un prompt esperando, lo despierta; si el sistema
    # está a medio arrancar, no molesta.
    s.sendall(b"\n")
    time.sleep(0.5)
    vaciar(s)
    s.sendall((orden + "\n").encode())
    print(leer(s, 4))


main()
