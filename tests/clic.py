#!/usr/bin/env python3
"""Mueve el ratón a unas coordenadas de la pantalla de la VM y pulsa."""
import json, socket, sys, time

SOCK = "/tmp/mikeos-qmp.sock"
ANCHO, ALTO = 1920, 1080

def qmp(s, cmd):
    s.sendall((json.dumps(cmd) + "\n").encode())
    time.sleep(0.25)
    try:
        return s.recv(65536).decode()
    except Exception:
        return ""

def main():
    x, y = int(sys.argv[1]), int(sys.argv[2])
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    s.settimeout(2)
    s.recv(65536)
    qmp(s, {"execute": "qmp_capabilities"})
    # El absolute pointer usa un rango de 0..32767 sobre cada eje.
    ax = int(x * 32767 / ANCHO)
    ay = int(y * 32767 / ALTO)
    qmp(s, {"execute": "input-send-event", "arguments": {"events": [
        {"type": "abs", "data": {"axis": "x", "value": ax}},
        {"type": "abs", "data": {"axis": "y", "value": ay}},
    ]}})
    time.sleep(0.4)
    qmp(s, {"execute": "input-send-event", "arguments": {"events": [
        {"type": "btn", "data": {"button": "left", "down": True}}]}})
    time.sleep(0.15)
    qmp(s, {"execute": "input-send-event", "arguments": {"events": [
        {"type": "btn", "data": {"button": "left", "down": False}}]}})
    print(f"clic en ({x},{y})")
    s.close()

main()
