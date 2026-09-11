# MIKE OS — Development Toolchain and C Compilation

## 1. Package: `development.mpk`
MIKE OS includes a self-contained native C toolchain packaged in `development.mpk`.

---

## 2. Components
- **TinyCC (`/usr/bin/tcc`)**: Ultra-fast, lightweight C compiler.
- **GCC Wrapper (`/usr/bin/gcc` and `/usr/bin/cc`)**: Automates compilation with embedded header directories.
- **System Headers (`/usr/include/`)**: Self-contained C headers (`stdio.h`, `stdlib.h`, `unistd.h`) with direct Linux x86_64 syscall implementations.

---

## 3. Usage Example

```c
// hello.c
#include <stdio.h>

int main() {
    printf("Hello from native C compiled directly inside MIKE OS!\n");
    return 0;
}
```

```bash
# Compiling and executing
gcc hello.c
```
