# MKShell — MIKE OS Native Shell (v0.2.0)

## Overview
**MKShell** (`/bin/mkshell`) is a lightweight native shell written in C specifically designed for MIKE OS.

---

## Features
- **Pipelining**: Supports multi-stage pipes (`cmd1 | cmd2 | cmd3`).
- **Redirections**: Supports output write (`>`), output append (`>>`), input (`<`), and file descriptor redirection.
- **Built-in Commands**: `cd`, `pwd`, `export`, `unset`, `alias`, `history`, `source`, `version`, `exit`, `help`.
- **Variable Expansion**: Expands `$VAR`, `$?` (last exit code), `$$` (PID), and `~` (home directory).
- **Configuration**: Loads `/etc/mkshell.rc` and `~/.mkshellrc` upon startup.
- **Prompt**: Informative, color-coded prompt showing user, host, current directory, and exit code on error.
