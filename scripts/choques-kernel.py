#!/usr/bin/env python3
"""¿Ha dejado algún parche dos #define con el mismo valor dentro de una familia?

Se llama desde build.sh después de aplicar build/kernel-patches/ y lo hace
plantarse si encuentra alguno.

Por qué existe: al pasar a Linux 7.2.9, el parche de la Type Cover de Surface
entró con fuzz y dejó, sin una sola queja, MT_QUIRK_HAS_TYPE_COVER_BACKLIGHT
en el mismo bit que MT_QUIRK_IGNORE_FEATURE_ID_MISMATCH, y la clase de la Type
Cover con el mismo número que la del ASUS ROG Z13. Compilaba, arrancaba, y le
estropeaba el teclado a otro equipo. Lo mismo el bit de btusb para la Marvell
de Surface, que ya estaba ocupado. Un parche que "aplica" no es un parche que
esté bien: el contexto coincide y el valor que añade puede estar usado veinte
líneas más abajo, donde el parche no mira.

Uso: choques-kernel.py <árbol del kernel> <commit base>
"""
import collections, re, subprocess, sys

arbol, base = sys.argv[1], sys.argv[2]

def git(*a):
    return subprocess.run(["git", "-C", arbol] + list(a),
                          capture_output=True, text=True).stdout.split("\n")

tocados = [f for f in git("diff", "--name-only", base) if f.endswith((".c", ".h"))]
tocados += [f for f in git("ls-files", "--others", "--exclude-standard") if f.endswith((".c", ".h"))]

DEF = re.compile(r'^#define\s+([A-Z][A-Z0-9_]*)\s+(BIT\(\d+\)|0x[0-9a-fA-F]+|\d+)\s*$', re.M)
malos = 0
for f in sorted(set(tocados)):
    try:
        texto = open(f"{arbol}/{f}", encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    familias = collections.defaultdict(lambda: collections.defaultdict(list))
    for nombre, valor in DEF.findall(texto):
        familia = "_".join(nombre.split("_")[:2])
        familias[familia][valor.lower()].append(nombre)
    for familia, valores in familias.items():
        # Una familia de tres o menos no es una tabla de bits o de clases:
        # FOO_MIN/FOO_DEFAULT valiendo lo mismo es normal.
        if len(valores) <= 3:
            continue
        for valor, nombres in valores.items():
            if len(nombres) > 1:
                print(f"  CHOQUE en {f}: {valor} = {', '.join(nombres)}")
                malos += 1
sys.exit(1 if malos else 0)
