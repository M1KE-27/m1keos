# MIKE Desktop — Arquitectura, Componentes y Uso

**MIKE Desktop** es una capa gráfica opcional, ultraligera, modular e independiente diseñada sobre **MIKE OS Core**.

---

## 1. Filosofía y Principios

1. **Modular e Independiente**: Se instala y elimina a través de MPM (`mpm install mike-desktop` / `mpm remove mike-desktop`) sin afectar al Core de MIKE OS.
2. **Minimalismo Visual Estricto**: Cero widgets recargados, cero transparencias pesadas, cero demonios residentes innecesarios.
3. **Stack Gráfico**:
   ```text
   Linux Kernel 7.2 (KMS / DRM VirtIO-GPU / Intel)
         ↓
       Mesa
         ↓
      Wayland
         ↓
     Hyprland (Compositor & Tiling Window Manager)
         ↓
    Quickshell (QML Top Panel & Workspaces)
         ↓
     MIKE UI (Temas Dark / Nord / Monochrome)
   ```

---

## 2. Componentes

* **Compositor**: `Hyprland` configurado con bordes limpios de 1px, tema oscuro `#101014` y acento cyan `#00d4ff`.
* **Barra Superior**: Waybar con configuración MIKE propia; Quickshell (`shell.qml`) queda como fallback para equipos donde Waybar no esté disponible.
* **Lanzador de Aplicaciones**: `m-launcher` (basado en `fuzzel` o menú rápido de terminal) invocado con la tecla `SUPER` o `SUPER + Espacio`.
* **Terminal**: `MTerminal` (GTK/VTE) ejecutando `MKShell`, con pestañas propias.
* **Controlador CLI**: `m-desktop` (`start`, `status`, `enable`, `disable`, `theme`, `config`).

---

## 3. Atajos de Teclado (Keybindings)

| Atajo | Acción |
| :--- | :--- |
| **`SUPER + Enter`** | Abre el terminal (`m-terminal` con `mkshell`) |
| **`CTRL + ALT + T`** | Abre MTerminal |
| **`CTRL + Shift + T`** | Nueva pestaña conservando el directorio actual |
| **`CTRL + PageUp/PageDown`** | Cambia de pestaña |
| **`CTRL + Shift + W`** | Cierra la pestaña actual |
| **`SUPER + Espacio`** | Abre el lanzador de aplicaciones (`m-launcher`) |
| **`SUPER + Q`** | Cierra la ventana activa |
| **`CTRL + ALT + S`** / **`SUPER + ALT + S`** | Captura una región y la copia automáticamente al clipboard |
| **`CTRL + ALT + ↑/↓`** / **`SUPER + ALT + ↑/↓`** | Ajusta el volumen en pasos de 5 (0–100) |
| **`SUPER + M`** | Sale de la sesión gráfica Hyprland |
| **`SUPER + F`** | Modo pantalla completa (fullscreen) |
| **`SUPER + V`** | Alterna modo flotante (toggle floating) |
| **`SUPER + [1-4]`** | Cambia al workspace 1–4 |
| **`SUPER + Shift + [1-4]`** | Mueve la ventana activa al workspace 1–4 |
| **`SUPER + rueda ↑/↓`** | Cambia circularmente entre los cuatro workspaces |
| **`SUPER + Flechas / HJKL`** | Navegación de foco entre ventanas |

---

## 4. Comandos de Administración (`m-desktop`)

```bash
# Iniciar sesión gráfica
m-desktop start

# Consultar estado de Wayland, Hyprland y GPU
m-desktop status

# Configurar arranque gráfico por defecto
m-desktop enable

# Restaurar arranque en consola TTY por defecto
m-desktop disable

# Listar o cambiar tema visual
m-desktop theme [dark|nord|monochrome]
```

---

## 5. Probar con QEMU en Modo Ventana Gráfica

MIKE OS arranca deliberadamente en consola para funcionar en cualquier equipo.
Desde MKShell usa `m-desktop start`; para cambiar el comportamiento persistente
usa `m-desktop enable` o `m-desktop disable`.

Para probar la aceleración VirtIO-GPU y la ventana gráfica de MIKE OS:

```bash
./scripts/run-qemu.sh --gui
```
