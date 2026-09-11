# MIKE OS — SSH Architecture and Security

## Overview
MIKE OS includes a drop-in static Dropbear SSH daemon configured for minimal attack surface.

## Features
- **Zero dynamic library dependencies** (fully static build).
- **Persistent host keys**: Keys are generated once and stored in `/etc/dropbear/`.
- **User isolation**: Supports `root` (UID 0) and unprivileged user `mike` (UID 1000).
- **Client utilities**: `dbclient` (aliased to `ssh`) and `scp`.

## Service Management
The SSH server is supervised by runit under `/etc/sv/dropbear`.
To restart or stop SSH:
```bash
m-service restart dropbear
m-service stop dropbear
```
