# Parches del kernel para hardware Surface

De dónde salen
--------------
Son los de [linux-surface](https://github.com/linux-surface/linux-surface),
serie 6.19, copiados tal cual. Ese proyecto es quien mantiene el soporte de
Microsoft Surface en Linux desde hace años; reescribirlo por nuestra cuenta
sería peor y además ya está hecho.

Se copian al repositorio en vez de descargarse al compilar a propósito: una
construcción no debería depender de que GitHub esté en pie, ni cambiar de
resultado según el día.

Por qué estos y no los dieciséis
--------------------------------
Nuestro kernel es el 7.2, y buena parte de lo que hacía falta en 6.x ya está
integrado río arriba. De los dieciséis de la serie, siete no aplican porque el
código que tocaban ya cambió (ipts, ithc, surface-button, surface-shutdown,
cameras, rtc, hid-surface). Los otros nueve sí, y son los que están aquí.

Se quedaron fuera también los "dirtyfrag-*", que no son de Surface: son
correcciones de red (rxrpc, xfrm) que linux-surface arrastra por su cuenta y
que no tienen nada que ver con este hardware.

El que de verdad importaba
--------------------------
`0014-amd-gpio.patch` arregla que la tabla ACPI de la **Surface Laptop 4 AMD**
(los dos tamaños, SKU 1952:1953 y 1958:1959) se deja sin declarar la
sobrescritura de la IRQ 7. Sin eso el kernel acaba sondeando el PIC antiguo y
sigue con él en un estado desconocido, que es justo el tipo de avería que
después aparece como dispositivos que tardan cuarenta segundos en enumerarse o
que no enumeran.

Cómo se aplican
---------------
`scripts/build.sh` los aplica en orden con `git apply` justo después del
`git checkout` del kernel, y **se planta si alguno falla**: un parche que no
entra en silencio es peor que no tenerlo, porque el resultado parece bueno y
no lo es.
