# MIKE OS — Networking and SSH

## 1. Network Architecture

MIKE OS manages network interfaces via `/etc/mikeos/network.conf` and the supervised `network` service.

### Configuration (`/etc/mikeos/network.conf`)

```sh
INTERFACE="eth0"
MODE="dhcp"                    # Options: dhcp or static
STATIC_IP="192.168.1.100/24"
GATEWAY="192.168.1.1"
DNS="1.1.1.1 8.8.8.8"
```

### Management via `m-network`

```bash
m-network status        # Displays interface IPs, routing table, and DNS
m-network test          # Tests connectivity with 1.1.1.1 and 8.8.8.8
m-network dhcp eth0     # Requests IP address using udhcpc
m-network static eth0 192.168.1.50/24 192.168.1.1
```

---

## 2. Dropbear SSH Server

MIKE OS includes a statically compiled Dropbear SSH server.

* **Host Keys**: Auto-generated on first boot in `/etc/dropbear/` (RSA, ECDSA, Ed25519).
* **Port**: 22 (forwarded to `localhost:2222` in QEMU).
* **Connecting from Host**:
  ```bash
  ssh -p 2222 root@localhost
  ssh -p 2222 mike@localhost
  ```
* **Client Tool**: `ssh` / `dbclient` and `scp` are pre-installed in `/usr/bin/`.

---

## Bluetooth — por qué no funcionaba, y cómo se arregló

Tres causas independientes, y las tres invisibles: ninguna dejaba un error a la
vista.

### 1. El driver se engancha y LUEGO falla al cargar el firmware

`btusb` (el Bluetooth de Intel, y la mayoría) hace `probe` primero y pide su
firmware después, en segundo plano. En MIKE OS todos los drivers van dentro del
kernel (`=y`), así que ese `probe` ocurre cuando el único sistema de archivos
montado es el initramfs — donde no hay firmware de Bluetooth:

```
Bluetooth: hci0: Direct firmware load for intel/ibt-19-0-4.sfi failed with error -2
Bluetooth: hci0: Failed to load Intel firmware file (-2)
```

Y aquí está lo que costó ver: **desde `/sys` eso es indistinguible de un
dispositivo que funciona**, porque tiene driver. `m-reintentar-drivers` sólo
rescataba dispositivos *sin* driver, así que el Bluetooth se saltaba siempre y
seguía muerto después de un arranque entero.

Ahora `m-reintentar-drivers` lee el propio registro del kernel, resuelve el
nombre del dispositivo (`hci0`, `1-5:1.0`, `0000:02:00.0` — el kernel usa las
tres formas), comprueba que el firmware **ya esté** en `/lib/firmware`, y hace
`unbind` + `bind`: eso rehace el `probe` entero con el firmware en su sitio. La
gráfica queda fuera a propósito — desengancharla deja la pantalla en negro.

### 2. Bloqueado por software, sin nadie que lo desbloquee

Sin udev nadie restaura el estado guardado de rfkill, y en muchos equipos —
casi todos los que vienen de Windows — el adaptador arranca bloqueado. Visto
desde fuera es idéntico a no tener Bluetooth: `bluetoothctl` dice *"No default
controller available"* y no hay ni un error.

`/etc/sv/bluetoothd/run` escribe ahora `0` en `/sys/class/rfkill/*/soft` de
todo lo que sea `bluetooth` o `wlan`, sin depender de la herramienta `rfkill`,
que no está en la imagen.

### 3. Sin `/etc/bluetooth/main.conf`

No existía. `bluetoothd` arrancaba con sus valores compilados, lo que dejaba al
azar dos cosas que aquí no pueden estarlo: que el adaptador se encienda solo
al aparecer (`AutoEnable`) y que unos cascos ya emparejados se reconecten al
encenderlos (`ReconnectUUIDs`, `JustWorksRepairing`).

### Cómo se comprueba

```sh
m-drivers --breve | grep Bluetooth     # estado y por qué
m-bluetooth estado                     # sin-adaptador | apagado | listo
m-hardware                             # el informe completo
```
