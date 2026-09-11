# Cómo colaborar

Gracias por mirar. Esto es un proyecto personal que se hizo público porque
alguien más puede aprender de él o mejorarlo.

## Antes de nada

**Pruébalo.** Descarga la imagen de <https://m1keos.duckdns.org>, grábala en un
USB y arráncala. La mitad de las buenas ideas salen de usar algo, no de leerlo.

## Reportar un fallo

Lo que más ayuda, por orden:

1. **Qué esperabas y qué pasó.** En esas palabras.
2. **En qué equipo.** La salida de `m-info`, o `m-doctor` si algo va mal.
3. **Cómo repetirlo.** Aunque sea "abro el Centro de Control y pulso Sistema".
4. **Una captura**, si se ve. `SUPER + S` la hace.

No hace falta que sepas dónde está el problema. Describir bien el síntoma vale
más que adivinar la causa.

## Cambiar código

```sh
git clone <este repositorio> mikeos     # sin espacios en la ruta, ver abajo
cd mikeos
./scripts/build.sh                      # la primera vez compila el kernel: tarda
./scripts/run-qemu.sh --gui --desktop
```

Para iterar sin reconstruir la imagen entera, con la máquina ya arrancada:

```sh
./scripts/dev.sh qml         # recarga la barra y el Centro de Control
./scripts/dev.sh scripts     # sincroniza las herramientas m-*
./scripts/dev.sh all
```

### Antes de mandar nada

```sh
./tests/humo.sh              # las 21 comprobaciones
```

Si tocaste el arranque, el instalador o el kernel, además:

```sh
./tests/probar-arranque-uefi.sh
```

## Cómo se escribe aquí

Tres cosas que se aplican a todo el proyecto:

**1. Los comentarios explican por qué, no qué.** El código ya dice qué hace. Lo
que no se puede recuperar leyéndolo es la razón: qué se probó antes, qué falló,
por qué esta forma y no la evidente.

```sh
# Mal:  incrementa el contador
# Bien: se cuenta aquí y no en el bucle porque el bucle se salta las
#       líneas vacías, y entonces el total no cuadraba con el archivo
```

**2. Los mensajes y los comentarios van en español**, igual que la interfaz. Es
la lengua del proyecto.

**3. Un punto no está hecho hasta que se ha visto funcionar.** No hasta que
compila: hasta que alguien lo ha mirado funcionando, o hay una prueba que lo
comprueba. `docs/plan-centro-de-control.md` lleva el registro de qué se verificó
y cómo, y está lleno de casos en los que el código era correcto y el
comportamiento no.

## Trampas conocidas

- **La ruta del proyecto no puede llevar espacios.** kbuild se niega en seco
  (`source directory cannot contain spaces or colons`) y el `make install` de
  BusyBox pasa rutas sin comillas.
- **Todo lo del kernel va compilado dentro (`=y`).** MIKE OS no monta
  `/lib/modules`, así que un driver en módulo es un driver que no existe.
- **Activa la virtualización en la BIOS** (`SVM Mode` en AMD, `VT-x` en Intel).
  Sin ella la máquina arranca unas tres veces más lenta y se cuelga bajo carga.
- **Secure Boot hay que desactivarlo** para arrancar el USB: el kernel no lleva
  la firma de Microsoft.

## Licencia

Lo que mandes se publica bajo la licencia MIT, igual que el resto. Ver
[LICENSE](LICENSE) y [AVISOS.md](AVISOS.md).
