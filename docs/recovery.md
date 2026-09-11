# MIKE OS — Recovery Mode and Troubleshooting

## 1. Entering Recovery Mode
To enter Recovery Mode, add the following parameter to the kernel command line during boot:

```text
mikeos_recovery=1
```

Or run via the runner script:
```bash
./scripts/run-qemu.sh --recovery
```

---

## 2. Recovery Environment
- The `/init` entrypoint immediately halts the normal boot process and launches `/bin/mkshell` as `root` directly on `/dev/console`.
- Virtual filesystems (`/proc`, `/sys`, `/dev`, `/run`, `/tmp`) are mounted.
- Services are **not** started, allowing safe recovery of broken network configs, corrupt user accounts, or broken storage mounts.

---

## 3. Emergency Repairs
- **Repair Filesystem**: `fsck.ext4 -y /dev/vda`
- **Reset User Passwords**: Edit `/etc/passwd` or `/etc/shadow`
- **Revert Package**: `mpm rollback`
- **Revert Kernel**: `mpm kernel rollback`
- **Reboot System**: `reboot -f`
