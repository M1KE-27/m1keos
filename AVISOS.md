# De quién es cada cosa

El código de MIKE OS —lo que hay en este repositorio— está bajo licencia MIT:
haz con él lo que quieras.

Pero la **imagen** que se descarga no es sólo este código. Dentro viaja
software escrito por otra gente, y cada pieza conserva su propia licencia.
Distribuir la imagen significa cumplirlas todas. Esto no es burocracia: son las
condiciones con las que esa gente permitió que su trabajo se usara.

## Lo que lleva la imagen

| Pieza | Licencia | Qué implica |
|---|---|---|
| **Linux** (el kernel) | GPL-2.0 | Copyleft. Si distribuyes un kernel modificado, tienes que ofrecer su código |
| **BusyBox** | GPL-2.0 | Igual |
| **bash** | GPL-3.0 | Igual, y más estricta con las patentes y el arranque bloqueado |
| **runit** | BSD de 3 cláusulas | Permisiva, hay que conservar el aviso |
| **Dropbear SSH** | MIT y otras | Permisiva |
| **TinyCC** | LGPL-2.1 | Permite enlazar, pide poder sustituir la biblioteca |
| **Hyprland** | BSD de 3 cláusulas | Permisiva |
| **Quickshell** | LGPL-3.0 | Permite enlazar, pide poder sustituirla |
| **Qt 6** | LGPL-3.0 | Igual. Por eso se enlaza dinámicamente y no estáticamente |
| **PipeWire**, **WirePlumber** | MIT | Permisiva |
| **Firmware** (`/lib/firmware`) | Cada uno el suyo | Casi todo binario redistribuible pero **no libre** |

## Dos cosas que conviene tener claras

**El kernel es GPL-2.0.** Este repositorio no lleva su código dentro: lleva las
opciones de configuración (`.config`) y un script que descarga el árbol oficial
de kernel.org fijado por commit exacto. Quien construya la imagen se baja el
código original. Si algún día MIKE OS parcheara el kernel, esos parches serían
GPL-2.0 y tendrían que publicarse; para eso existe la carpeta
`kernel-parches/`.

**El firmware no es libre.** Los binarios de `/lib/firmware` (gráficos AMD,
WiFi Qualcomm…) los publican los fabricantes con permiso para redistribuirlos,
pero sin su código fuente. Sin ellos no hay gráficos ni red en un portátil de
verdad; con ellos, la imagen no es 100 % software libre. Se dice aquí en vez de
dejarlo implícito.

## Si redistribuyes la imagen

Acompáñala de este archivo y del `LICENSE`. Es lo mínimo, y es lo justo con
quien escribió todo lo demás.
