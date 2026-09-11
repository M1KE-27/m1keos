# MIKE OS — System Architecture (v0.2.0 Core)

**MIKE OS** is an independent, ultra-lightweight, customizable, and high-performance Linux/Unix distribution built from scratch without systemd.

---

## 1. System Layering

MIKE OS follows a strict, decoupled two-layer design:

```text
┌─────────────────────────────────────────────────────────────┐
│                      MIKE DESKTOP (Optional)                │
│       Hyprland · Wayland · Quickshell · MIKE UI Theme       │
├─────────────────────────────────────────────────────────────┤
│                      MIKE OS CORE (Base System)             │
│   Linux Kernel 7.2 (x86_64) · Runit 2.1.2 · Unix Userspace  │
│   Networking · Storage · Users & Security · Dropbear SSH    │
│   MPM (Package Manager) · MCore Suite · MKShell · Recovery  │
└─────────────────────────────────────────────────────────────┘
```

The Core is completely autonomous and operates at maximum performance without any graphical dependencies.

---

## 2. Fundamental Design Principles

1. **Strictly Customizable**: Every system configuration resides in plain text under `/etc/mikeos/`.
2. **Ultra-Fast & Lightweight**: Sub-second boot times (**~0.60s**), low RAM consumption (**45–80 MB**).
3. **Zero Systemd**: Utilizes **runit 2.1.2** as true PID 1 and service supervisor.
4. **POSIX/Unix Standard**: Standard commands powered by static BusyBox, native tools, and full shell piping.
5. **Atomic & Verifiable**: Every package and kernel operation managed through MPM with SHA256 validation and instant rollback.

---

## 3. Filesystem Hierarchy

```text
/
├── boot/                   # Kernel images (vmlinuz, vmlinuz.old)
├── bin/ & sbin/            # Essential binaries (runit, busybox, mkshell)
├── usr/
│   ├── bin/ & sbin/        # MCore utilities, MPM, Dropbear SSH, compiler tools
│   ├── lib/ & include/     # Static libraries and C header toolchains
│   └── share/              # System scripts (e.g. udhcpc hooks)
├── etc/
│   ├── mikeos/             # Declarative system settings (system, network, boot)
│   ├── runit/              # Stages 1 (init), 2 (supervise), 3 (shutdown)
│   ├── sv/                 # Available supervised service definitions
│   └── dropbear/           # SSH server host keys
├── var/
│   ├── service/            # Active services monitored by runsvdir
│   ├── log/                # System log files (/var/log/messages)
│   └── lib/mpm/            # MPM database, packages repository, and backups
├── dev/, proc/, sys/       # Virtual kernel interfaces
└── root/, home/mike/       # User home directories with .mkshellrc
```
