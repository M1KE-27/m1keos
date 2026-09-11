# MIKE OS — Service Supervision with Runit

MIKE OS uses **runit 2.1.2** exclusively as its init and service supervisor.

---

## 1. Directory Structure

* `/etc/sv/<service>/run`: Executable service run script.
* `/etc/sv/<service>/supervise/`: Service supervision state directory.
* `/var/service/<service>`: Symlink to `/etc/sv/<service>` representing active, monitored services.

---

## 2. Core Services

| Service | Script | Purpose |
| :--- | :--- | :--- |
| `console` | `/etc/sv/console/run` | Spawns interactive MKShell on `/dev/console` with job control. |
| `syslog` | `/etc/sv/syslog/run` | Captures system logs into `/var/log/messages`. |
| `network` | `/etc/sv/network/run` | Manages network interfaces and DHCP client (`udhcpc`). |
| `dropbear` | `/etc/sv/dropbear/run` | Runs SSH daemon on port 22 with auto-generated host keys. |

---

## 3. Controlling Services with `m-service`

```bash
# List all services and their status
m-service list

# Enable and start a service
m-service enable dropbear
m-service start dropbear

# Stop and disable a service
m-service stop dropbear
m-service disable dropbear

# Restart a service
m-service restart network
```
