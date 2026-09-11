/*
 * m-sudo - Escalada de privilegios para MIKE OS.
 * Binario setuid-root: valida que el invocador pertenezca a "wheel" y
 * ejecuta el comando como root directamente, sin pedir contraseña (las
 * cuentas del sistema están bloqueadas por diseño; ver /etc/shadow).
 *
 * Parsea /etc/passwd y /etc/group a mano en vez de usar getpwuid()/
 * getgrouplist(): esas funciones dependen de NSS, que hace dlopen() de
 * libnss_files.so incluso en binarios "estáticos" y revienta con
 * segfault si esa .so no está disponible tal cual la vio el enlazador.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

static int find_user(uid_t uid, char *name_out, size_t name_len, gid_t *gid_out) {
    FILE *f = fopen("/etc/passwd", "r");
    if (!f) return 0;
    char line[512];
    int found = 0;
    while (fgets(line, sizeof(line), f)) {
        char *name = strtok(line, ":");
        char *pass = strtok(NULL, ":");
        char *uid_s = strtok(NULL, ":");
        char *gid_s = strtok(NULL, ":");
        (void)pass;
        if (!name || !uid_s || !gid_s) continue;
        if ((uid_t)atol(uid_s) == uid) {
            snprintf(name_out, name_len, "%s", name);
            *gid_out = (gid_t)atol(gid_s);
            found = 1;
            break;
        }
    }
    fclose(f);
    return found;
}

static int in_wheel(const char *username, gid_t primary_gid) {
    FILE *f = fopen("/etc/group", "r");
    if (!f) return 0;
    char line[1024];
    int result = 0;
    while (fgets(line, sizeof(line), f)) {
        char *name = strtok(line, ":");
        char *pass = strtok(NULL, ":");
        char *gid_s = strtok(NULL, ":");
        char *members = strtok(NULL, "\n");
        (void)pass;
        if (!name || strcmp(name, "wheel") != 0) continue;
        if (gid_s && (gid_t)atol(gid_s) == primary_gid) { result = 1; break; }
        if (members) {
            char *tok = strtok(members, ",");
            while (tok) {
                if (strcmp(tok, username) == 0) { result = 1; break; }
                tok = strtok(NULL, ",");
            }
        }
        break;
    }
    fclose(f);
    return result;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Uso: m-sudo <comando> [argumentos...]\n");
        return 1;
    }

    uid_t ruid = getuid();
    if (ruid != 0) {
        char username[256];
        gid_t primary_gid;
        if (!find_user(ruid, username, sizeof(username), &primary_gid)) {
            fprintf(stderr, "m-sudo: no se pudo resolver el usuario actual (uid %d)\n", (int)ruid);
            return 1;
        }
        if (!in_wheel(username, primary_gid)) {
            fprintf(stderr, "m-sudo: '%s' no tiene permisos de superusuario (no está en wheel).\n", username);
            return 1;
        }
    }

    if (setgid(0) != 0 || setuid(0) != 0) {
        perror("m-sudo: no se pudo elevar privilegios");
        return 1;
    }

    execvp(argv[1], &argv[1]);
    fprintf(stderr, "m-sudo: %s: %s\n", argv[1], strerror(errno));
    return 127;
}
