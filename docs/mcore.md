# MCore — Native Administration Tool Suite

MCore is a suite of dedicated utilities installed in `/usr/bin/` for system monitoring, service control, user administration, and maintenance.

---

## Utility Directory

| Utility | Description | Usage Example |
| :--- | :--- | :--- |
| `m-system` | Live telemetry, CPU, RAM, disk, and profile stats. | `m-system` |
| `m-info` / `m-fastfetch` | Fastfetch nativo con logo M de MIKE y especificaciones del sistema. | `m-info` |
| `m-doctor` | Comprehensive 6-point system health checker. | `m-doctor` |
| `m-service` | Runit service manager (enable, start, stop, restart). | `m-service list` |
| `m-network` | Network interface and DNS manager. | `m-network status` |
| `m-user` | User and group account administrator. | `m-user list` |
| `m-disk` | Block device and mount point viewer. | `m-disk` |
| `m-log` | Log inspector for `/var/log/messages` and `dmesg`. | `m-log -f` |
| `m-sudo` | Lightweight privilege elevator for `wheel` users. | `m-sudo <cmd>` |
| `m-install` | Automated disk partitioning, format, and installer. | `m-install /dev/sdb` |
| `m-energia` | Perfiles de energía (máximo, equilibrado, ahorro, automático), suspender e hibernar, y qué hace la tapa. | `m-energia maximo` |
| `m-drivers` | Analiza TODO el equipo y dice en qué estado está cada componente y qué le falta. | `m-drivers` |
| `m-hardware` | El informe largo: cada dispositivo PCI y USB con su driver, su firmware y su servicio. | `m-hardware` |
| `m-reintentar-drivers` | Vuelve a probar los dispositivos que arrancaron sin driver o sin firmware. | (lo llama el arranque) |
| `m-tapa` | Qué hacer al cerrar y abrir la tapa del portátil. | `m-tapa cerrar` |


---

## Energía — `m-energia`

No había nada de gestión de energía: el kernel arrancaba con sus valores de
fábrica, pensados para un servidor enchufado a la pared. En un portátil eso son
horas de batería tiradas; en un sobremesa, rendimiento dejado sin usar.

Cuatro perfiles:

| Perfil | Qué hace |
| :--- | :--- |
| `maximo` | El procesador no baja de frecuencia y **nada** se duerme: ni USB, ni PCI Express, ni el audio. Lo más rápido que da el equipo. |
| `rendimiento` | Frecuencia bajo demanda, disco siempre despierto. El punto medio. |
| `ahorro` | Todo lo que puede dormirse, duerme; las escrituras se agrupan. |
| `auto` | **Sobremesa** (sin batería): máximo, sin tener que pedirlo. **Portátil**: equilibrado con cargador, ahorro con batería. |

La elección se guarda en `/etc/mikeos/energia` — en `/etc` y no en el `$HOME`
de nadie, porque quien la escribe es la persona que usa el escritorio y quien
la lee es el servicio de runit, que corre como root.

Suspender e hibernar sólo se ofrecen si el equipo los publica de verdad en
`/sys/power/state`, e hibernar además exige swap del tamaño de la RAM. Un menú
que ofrece hibernar donde no cabe la memoria promete que el portátil se
despierta cuando en realidad se va a apagar con el trabajo dentro.

Qué hace la tapa se guarda en `/etc/mikeos/tapa` (`pantalla`, `suspender`,
`hibernar`, `nada`) y se elige en el Centro de Control. La sesión se bloquea
siempre al cerrar, sea cual sea la opción.

---

## Controladores — `m-drivers`

Recorre PCI y USB leyendo los identificadores que publica el propio hardware, y
de cada componente dice en cuál de estos estados está. Son averías distintas,
con soluciones distintas, que desde fuera se veían todas igual:

| Estado | Significa |
| :--- | :--- |
| `ok` | Funciona. |
| `sin-driver` | El kernel no tiene quien lo maneje. |
| `sin-firmware` | Hay driver, pero le falta un archivo de firmware. |
| `apagado` | Está todo, pero el servicio que lo usa no está en pie. |
| `mejorable` | Funciona, y hay un paquete que lo hace ir mejor. |

Cubre gráfica, red (PCI **y** USB), Bluetooth, sonido, entrada, cámara,
almacenamiento, procesador y batería.

Tres salidas del mismo análisis, para que el panel y la terminal no puedan
decir cosas distintas:

- sin argumentos, el informe para leerlo;
- `--json`, lo que lee el Centro de Control;
- `--breve`, líneas `COMP|categoría|nombre|estado|detalle` para la pantalla de
  bienvenida, que está escrita en C.

`--breve` existe porque la bienvenida leía la salida **bonita** buscando una
línea que empezara por `Recomendado:`. Cualquier cambio de formato la dejaba
mostrando datos vacíos o viejos sin un solo error.
