#!/usr/bin/env python3
"""Escribe texto en la consola de la máquina virtual, como si hubiera alguien
delante del teclado.

Hace falta para los casos en los que el sistema arranca pero no llega a
levantar SSH: sin esto, la única forma de saber qué pasa dentro es mirar una
captura y adivinar. Con esto se le pueden hacer preguntas.

    ./tests/teclear.py "ls -la /bin/sh" --enter
"""
import json
import socket
import sys
import time

SOCK = "/tmp/mikeos-qmp.sock"

# QMP habla de teclas por su nombre, no por su carácter. Esto traduce lo que se
# escribe a la combinación que hay que enviar.
ESPECIALES = {
    " ": "spc", "-": "minus", "=": "equal", "/": "slash", "\\": "backslash",
    ".": "dot", ",": "comma", ";": "semicolon", "'": "apostrophe",
    "[": "bracket_left", "]": "bracket_right", "`": "grave_accent",
    "\n": "ret", "\t": "tab",
}
CON_MAYUS = {
    "_": "minus", "+": "equal", "?": "slash", "|": "backslash", ">": "dot",
    "<": "comma", ":": "semicolon", '"': "apostrophe", "{": "bracket_left",
    "}": "bracket_right", "~": "grave_accent", "!": "1", "@": "2", "#": "3",
    "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
}


def teclas(texto):
    for c in texto:
        if c in ESPECIALES:
            yield [ESPECIALES[c]]
        elif c in CON_MAYUS:
            yield ["shift", CON_MAYUS[c]]
        elif c.isupper():
            yield ["shift", c.lower()]
        elif c.isalnum():
            yield [c]
        # Lo que no se sepa traducir se salta en vez de mandar basura.


def main():
    texto = sys.argv[1] if len(sys.argv) > 1 else ""
    enter = "--enter" in sys.argv

    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    s.settimeout(5)
    s.recv(65536)

    def q(cmd):
        s.sendall((json.dumps(cmd) + "\n").encode())
        time.sleep(0.05)
        try:
            return s.recv(65536)
        except Exception:
            return b""

    q({"execute": "qmp_capabilities"})

    for combo in teclas(texto):
        q({"execute": "send-key", "arguments": {
            "keys": [{"type": "qcode", "data": k} for k in combo]}})
    if enter:
        q({"execute": "send-key", "arguments": {
            "keys": [{"type": "qcode", "data": "ret"}]}})
    s.close()


main()
