# MIKE OS — Boot Process and Initialization

## 1. Boot Stages

```text
BIOS / UEFI
    │
    ▼
Linux Kernel (bzImage)
    │
    ▼
/init (Universal PID 1 Entrypoint)
    │
    ├── Mode Recovery (mikeos_recovery=1) -> Emergency Shell
    │
    ├── Persistent Disk Mode (root=/dev/vda)
    │     └── Mount ext4 root -> switch_root -> /sbin/runit
    │
    └── In-Memory Mode (initramfs)
          └── Direct execution -> /sbin/runit
```

---

## 2. Kernel Parameters Supported

* `root=/dev/vda rw`: Selects persistent root block device.
* `console=ttyS0` or `console=tty0`: Configures primary system console.
* `mikeos_recovery=1`: Boots directly into emergency root shell.
* `mikeos_benchmark=1`: Runs telemetry benchmark and halts.
* `mikeos_test_suite=1`: Executes the 21-check automated test suite.

---

## 3. Runit Stage Flow

1. **Stage 1 (`/etc/runit/1`)**: Mounts virtual filesystems (`/proc`, `/sys`, `/dev`, `/dev/pts`, `/run`, `/tmp`), brings up loopback, sets hostname from `/etc/mikeos/system.conf`, and displays the welcome banner.
2. **Stage 2 (`/etc/runit/2`)**: Starts `runsvdir` supervising `/var/service`.
3. **Stage 3 (`/etc/runit/3`)**: Gracefully shuts down all services, syncs storage, unmounts filesystems, and halts/reboots.
