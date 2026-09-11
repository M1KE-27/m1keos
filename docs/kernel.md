# MIKE OS — Kernel Management and Lifecycle

## 1. Overview
The Linux Kernel in MIKE OS (version 7.2.0, x86_64) is optimized for ultra-fast boot times, embedded drivers (ext4, virtio_blk, virtio_net, devtmpfs), and zero systemd dependencies.

---

## 2. Kernel Lifecycle via MPM

MPM manages the kernel layout under `/boot`:

* `/boot/vmlinuz`: Current active kernel.
* `/boot/vmlinuz.old`: Previous bootable fallback kernel.

### Commands

```bash
# List installed kernels
mpm kernel list

# Install a new kernel bzImage safely
mpm kernel install /path/to/new_bzImage

# Rollback to the previous working kernel
mpm kernel rollback

# Remove older kernel
mpm kernel remove 7.1.0
```

---

## 3. Kernel Configuration Principles
* `CONFIG_BLK_DEV_INITRD=y`: Embedded initramfs support.
* `CONFIG_DEVTMPFS=y` & `CONFIG_DEVTMPFS_MOUNT=y`: Auto-mounted device nodes.
* `CONFIG_EXT4_FS=y`: Native rootfs filesystem support.
* `CONFIG_VIRTIO_BLK=y` & `CONFIG_VIRTIO_NET=y`: Hypervisor acceleration.
