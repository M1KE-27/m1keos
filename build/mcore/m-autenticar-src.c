/*
 * m-autenticar - comprueba la contraseña de una cuenta de MIKE OS.
 *
 * Binario setuid-root. Existe porque /etc/shadow sólo lo puede leer root, y
 * la pantalla de bloqueo corre como el usuario normal: sin esto no hay forma
 * de saber si la contraseña que han escrito es la buena.
 *
 * Por qué no usa crypt():
 *   MIKE OS no lleva libcrypt. Lo que sí lleva, y ya se usa para media
 *   docena de cosas más, es busybox, cuyo "cryptpw" implementa sha512crypt.
 *   Antes que escribir criptografía a mano -- donde un fallo sutil significa
 *   que nadie puede entrar, o peor, que entra cualquiera -- se reutiliza la
 *   implementación que el sistema ya tiene y en la que ya confía para fijar
 *   las contraseñas con "passwd".
 *
 * Cómo se usa:
 *   La contraseña entra por la ENTRADA ESTÁNDAR, nunca por argumentos: lo que
 *   se pasa en argv lo ve cualquiera con un "ps".
 *
 *     printf '%s' "$clave" | m-autenticar          # la cuenta que invoca
 *     printf '%s' "$clave" | m-autenticar mike     # sólo root puede pedir otra
 *
 *   Salida: 0 correcta, 1 incorrecta, 2 la cuenta no tiene contraseña,
 *   3 la cuenta está bloqueada, 4 error. No imprime nada por la salida
 *   estándar: el código de salida es toda la respuesta.
 *
 * Parsea /etc/shadow y /etc/passwd a mano, igual que m-sudo y por el mismo
 * motivo: getpwuid()/getspnam() pasan por NSS, que hace dlopen() incluso en
 * binarios estáticos y revienta si la .so no está tal cual la vio el
 * enlazador.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>

#define BUSYBOX "/bin/busybox"
#define MAX_CLAVE 256
#define MAX_HASH 512

/* Se espera esto tras cada intento fallido. No impide un ataque decidido,
 * pero convierte "probar el diccionario entero" en algo que tarda semanas en
 * vez de minutos, que es para lo que sirve una pantalla de bloqueo. */
#define ESPERA_FALLO_US 1500000

/* Comparación en tiempo constante: con strcmp, el tiempo que tarda en decir
 * que no delata cuántos caracteres del hash eran correctos. */
static int iguales_seguro(const char *a, const char *b) {
    size_t la = strlen(a), lb = strlen(b);
    unsigned char dif = (unsigned char)(la != lb);
    size_t n = la < lb ? la : lb;
    for (size_t i = 0; i < n; i++)
        dif |= (unsigned char)(a[i] ^ b[i]);
    return dif == 0;
}

/* Borra de verdad. Un memset normal lo puede eliminar el optimizador al ver
 * que nadie vuelve a leer el búfer. */
static void borrar(void *p, size_t n) {
    volatile unsigned char *v = p;
    while (n--) *v++ = 0;
}

static int nombre_de_uid(uid_t uid, char *salida, size_t len) {
    FILE *f = fopen("/etc/passwd", "r");
    if (!f) return 0;
    char linea[512];
    int hallado = 0;
    while (fgets(linea, sizeof(linea), f)) {
        char *nombre = strtok(linea, ":");
        char *pass = strtok(NULL, ":");
        char *uid_s = strtok(NULL, ":");
        (void)pass;
        if (!nombre || !uid_s) continue;
        if ((uid_t)atol(uid_s) == uid) {
            snprintf(salida, len, "%s", nombre);
            hallado = 1;
            break;
        }
    }
    fclose(f);
    return hallado;
}

static int hash_de_usuario(const char *usuario, char *salida, size_t len) {
    FILE *f = fopen("/etc/shadow", "r");
    if (!f) return 0;
    char linea[1024];
    int hallado = 0;
    while (fgets(linea, sizeof(linea), f)) {
        linea[strcspn(linea, "\n")] = '\0';
        char *nombre = strtok(linea, ":");
        char *hash = strtok(NULL, ":");
        if (!nombre || !hash) continue;
        if (strcmp(nombre, usuario) == 0) {
            snprintf(salida, len, "%s", hash);
            hallado = 1;
            break;
        }
    }
    fclose(f);
    return hallado;
}

/*
 * Extrae "$metodo$sal$" de un hash tipo "$6$sal$resumen". cryptpw necesita el
 * método y la sal por separado para reproducir el mismo resumen.
 */
static int partir_hash(const char *hash, char *metodo, size_t lm, char *sal, size_t ls) {
    /* Sin "$" delante es DES: dos caracteres de sal y nada más. busybox
     * todavía cifra así por defecto, así que hay cuentas por ahí con este
     * formato y dejarlas fuera sería encerrar a su dueño. Se acepta para
     * poder entrar; avisar de que es débil es cosa de m-clave. */
    if (hash[0] != '$') {
        if (strlen(hash) < 13) return 0;
        if (lm < 4 || ls < 3) return 0;
        memcpy(metodo, "des", 4);
        memcpy(sal, hash, 2); sal[2] = '\0';
        return 1;
    }
    const char *p1 = strchr(hash + 1, '$');
    if (!p1) return 0;
    const char *p2 = strchr(p1 + 1, '$');
    if (!p2) return 0;

    size_t nm = (size_t)(p1 - (hash + 1));
    size_t ns = (size_t)(p2 - (p1 + 1));
    if (nm == 0 || nm >= lm || ns == 0 || ns >= ls) return 0;

    memcpy(metodo, hash + 1, nm); metodo[nm] = '\0';
    memcpy(sal, p1 + 1, ns);      sal[ns] = '\0';
    return 1;
}

/* Traduce el número de método de crypt al nombre que entiende cryptpw. */
static const char *nombre_metodo(const char *metodo) {
    if (strcmp(metodo, "6") == 0) return "sha512";
    if (strcmp(metodo, "5") == 0) return "sha256";
    if (strcmp(metodo, "1") == 0) return "md5";
    if (strcmp(metodo, "des") == 0) return "des";
    return NULL;
}

/*
 * Calcula el hash de "clave" con ese método y esa sal, llamando a cryptpw.
 *
 * Antes de ejecutarlo suelta los privilegios de root: cryptpw no los necesita
 * para nada, y así lo único que corre como root es la lectura de /etc/shadow,
 * que ya ha terminado. Si el exec fallara o busybox fuera otro binario del
 * que creemos, no habría root que aprovechar.
 */
static int calcular_hash(const char *metodo, const char *sal,
                         const char *clave, char *salida, size_t len) {
    int a_hijo[2], del_hijo[2];
    if (pipe(a_hijo) != 0) return 0;
    if (pipe(del_hijo) != 0) { close(a_hijo[0]); close(a_hijo[1]); return 0; }

    pid_t pid = fork();
    if (pid < 0) {
        close(a_hijo[0]); close(a_hijo[1]);
        close(del_hijo[0]); close(del_hijo[1]);
        return 0;
    }

    if (pid == 0) {
        /* Sin vuelta atrás: si setuid falla, no se ejecuta nada. */
        if (setgid(getgid()) != 0) _exit(127);
        if (setuid(getuid()) != 0) _exit(127);
        if (getuid() != geteuid()) _exit(127);

        dup2(a_hijo[0], STDIN_FILENO);
        dup2(del_hijo[1], STDOUT_FILENO);
        close(a_hijo[0]); close(a_hijo[1]);
        close(del_hijo[0]); close(del_hijo[1]);
        /* El error de cryptpw no interesa y no debe ensuciar la consola. */
        int nulo = open("/dev/null", O_WRONLY);
        if (nulo >= 0) { dup2(nulo, STDERR_FILENO); close(nulo); }

        char *args[] = { (char *)"busybox", (char *)"cryptpw",
                         (char *)"-m", (char *)metodo,
                         (char *)"-S", (char *)sal, NULL };
        char *entorno[] = { NULL };   /* entorno vacío: nada heredado */
        execve(BUSYBOX, args, entorno);
        _exit(127);
    }

    close(a_hijo[0]);
    close(del_hijo[1]);

    /* La contraseña va por la tubería, nunca por argv. */
    ssize_t n = write(a_hijo[1], clave, strlen(clave));
    (void)n;
    close(a_hijo[1]);

    size_t total = 0;
    ssize_t leidos;
    while (total + 1 < len &&
           (leidos = read(del_hijo[0], salida + total, len - total - 1)) > 0)
        total += (size_t)leidos;
    salida[total] = '\0';
    close(del_hijo[0]);

    int estado = 0;
    waitpid(pid, &estado, 0);

    salida[strcspn(salida, "\r\n")] = '\0';
    /* No se exige que empiece por "$": un hash DES no lo lleva. */
    return WIFEXITED(estado) && WEXITSTATUS(estado) == 0 && salida[0] != '\0';
}

int main(int argc, char **argv) {
    uid_t quien = getuid();
    char usuario[256];

    if (argc > 1) {
        /* Preguntar por otra cuenta es cosa de root: si no, cualquiera podría
         * usar esto para probar contraseñas ajenas a su antojo. */
        if (quien != 0) return 4;
        snprintf(usuario, sizeof(usuario), "%s", argv[1]);
    } else if (!nombre_de_uid(quien, usuario, sizeof(usuario))) {
        return 4;
    }

    char hash[MAX_HASH];
    if (!hash_de_usuario(usuario, hash, sizeof(hash))) return 4;

    /* "!" o "!..." = cuenta bloqueada; "" = sin contraseña. Se distinguen
     * porque quien llama tiene que poder decirlo: una cuenta sin contraseña
     * no se puede bloquear, y hay que avisar en vez de dejar entrar. */
    if (hash[0] == '\0') return 2;
    if (hash[0] == '!' || hash[0] == '*') return 3;

    char clave[MAX_CLAVE];
    size_t n = 0;
    int c;
    while (n + 1 < sizeof(clave) && (c = fgetc(stdin)) != EOF) {
        if (c == '\n') break;
        clave[n++] = (char)c;
    }
    clave[n] = '\0';

    char metodo[32], sal[128];
    if (!partir_hash(hash, metodo, sizeof(metodo), sal, sizeof(sal))) {
        borrar(clave, sizeof(clave));
        return 4;
    }
    const char *m = nombre_metodo(metodo);
    if (!m) { borrar(clave, sizeof(clave)); return 4; }

    char calculado[MAX_HASH];
    int ok = calcular_hash(m, sal, clave, calculado, sizeof(calculado))
             && iguales_seguro(calculado, hash);

    borrar(clave, sizeof(clave));
    borrar(calculado, sizeof(calculado));

    if (!ok) usleep(ESPERA_FALLO_US);
    return ok ? 0 : 1;
}
