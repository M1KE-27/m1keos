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
