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
