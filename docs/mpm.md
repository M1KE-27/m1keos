# MPM — MIKE Package Manager (v0.2.0 Core)

**MPM** is the central package management and deployment system for MIKE OS.

---

## 1. Package Structure (`.mpk`)

An `.mpk` package is a compressed archive containing:

```text
package-name-version-release-arch.mpk
├── meta.json         # Metadata (name, version, dependencies, origin, license, sha256)
├── PRE_INSTALL       # Optional pre-installation hook
├── POST_INSTALL      # Optional post-installation hook
└── data.tar.gz       # Payloads to deploy to root filesystem
```

### Example `meta.json`:
```json
{
  "name": "mcore",
  "version": "0.1.0",
  "release": "mike1",
  "arch": "x86_64",
  "category": "core",
  "license": "MIT",
  "origin": "https://mikeos.local",
  "description": "Suite de herramientas fundamentales del sistema MIKE OS",
  "dependencies": [],
  "size": "45KB"
}
```

---

## 2. Command Reference

```bash
# Search packages
mpm search <query>

# Show detailed package information
mpm info <package>

# Install with SHA256 validation & automatic rollback snapshot
mpm install <package>

# Uninstall package and remove associated files
mpm remove <package>

# List installed packages
mpm list

# Sync repository indices
mpm update

# Upgrade installed packages with newer repo versions
mpm upgrade

# Clean cached packages
mpm clean

# Verify installed packages integrity
mpm verify [package]

# Instant rollback of previous change
mpm rollback

# Kernel management
mpm kernel list
mpm kernel install <bzImage>
mpm kernel rollback
```
