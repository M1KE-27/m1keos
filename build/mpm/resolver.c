/*
 * resolver - motor de dependencias de MPM para los repositorios de Arch.
 *
 * No es una orden que el usuario ejecute: vive en /usr/lib/mpm y lo invoca
 * "mpm install". Antes era un programa aparte llamado m-arch-install, y esa
 * separación obligaba a saber qué gestor usar para cada cosa.
 *
 * Cómo resuelve
 * -------------
 * La versión anterior consultaba la API de búsqueda de archlinux.org una vez
 * por paquete y otra por cada dependencia, en cascada. Instalar Firefox
 * lanzaba cientos de peticiones encadenadas: tardaba varios minutos y acababa
 * fallando cuando el servidor cortaba por exceso de ritmo.
 *
 * Ahora /usr/lib/mpm/sync descarga el catálogo completo una vez y lo deja en
 * /var/lib/mpm/sync/index.tsv. Toda la resolución ocurre en memoria, sin red,
 * y sólo se descargan los .pkg.tar.zst que realmente hagan falta -- todos a la
 * vez, no uno detrás de otro.
 *
 * Dependencias virtuales
 * ----------------------
 * Muchas dependencias de Arch no nombran un paquete sino una capacidad:
 * firefox pide "ttf-font" y nautilus pide "libnautilus-extension.so". Ninguno
 * de los dos existe como paquete. El resolutor anterior los daba por perdidos
 * y seguía, así que Firefox quedaba instalado sin una sola fuente (texto
 * invisible) y Nautilus sin su librería. El índice incluye qué paquete provee
 * cada nombre virtual y aquí se traduce antes de resolver.
 *
 * Los paquetes de PKG_BASE nunca se tocan: son los que MIKE OS ya trae y
 * sobrescribirlos (glibc, bash, coreutils...) dejaría el sistema inservible a
 * mitad de instalación. El resto sí se instala, y es seguro porque el rootfs
 * base se construye copiando librerías de un host Arch: mismo ABI.
 *
 * Integridad: cada descarga se verifica contra el SHA256 que publica el propio
 * catálogo del repositorio. No hay verificación de firma GPG todavía; la
 * cadena de confianza llega hasta el HTTPS del espejo oficial.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <sys/statvfs.h>

#define INDICE_DEF  "/var/lib/mpm/sync/index.tsv"
/* Pieza interna de MPM, no una orden suelta en /usr/bin: quien instala algo
 * escribe "mpm install" y no tiene por qué conocer estos nombres. */
#define SYNC        "/usr/lib/mpm/sync"
#define ESPEJO_DEF  "https://geo.mirror.pkgbuild.com"
#define HASH_SIZE   65536          /* potencia de 2 > 2x el nº de entradas */
#define MAX_COLA    16384      /* cabe el catálogo entero: nunca se trunca */

/* Paquetes que forman el sistema base de MIKE OS. Reinstalarlos desde Arch
 * sobrescribiría el intérprete dinámico, la shell o las utilidades básicas
 * mientras el propio instalador se está ejecutando. */
static const char *PKG_BASE[] = {
    "glibc", "gcc-libs", "libgcc", "bash", "sh", "coreutils", "filesystem",
    "linux-api-headers", "tzdata", "iana-etc", "licenses", "shadow", "pam",
    "util-linux", "util-linux-libs", "systemd", "systemd-libs", "dbus",
    "ncurses", "readline", "zlib", "bzip2", "xz", "zstd", "gzip", "tar",
    "openssl", "ca-certificates", "ca-certificates-utils",
    "ca-certificates-mozilla", "curl", "jq", "findutils", "grep", "sed",
    "gawk", "procps-ng", "psmisc", "e2fsprogs", "busybox", "wget",
    NULL
};

/* Cuando varios paquetes proveen el mismo nombre virtual hay que elegir uno.
 * pacman se lo pregunta al usuario; aquí se decide sin preguntar, porque una
 * instalación no debe pararse a mitad. Estas son las elecciones con criterio;
 * para el resto vale el primero que aparezca en el catálogo. */
static const char *PREFERIDOS[][2] = {
    { "ttf-font",        "noto-fonts"       },  /* cobertura Unicode amplia */
    { "sh",              "bash"             },
    { "awk",             "gawk"             },
    { "libgl",           "mesa"             },
    { "libglvnd",        "mesa"             },
    { "libegl",          "mesa"             },
    { "libgles",         "mesa"             },
    { "vulkan-driver",   "vulkan-swrast"    },
    { "opengl-driver",   "mesa"             },
    { "java-runtime",    "jre-openjdk"      },
    { "ttf-font-nerd",   "ttf-nerd-fonts-symbols" },
    { NULL, NULL }
};

/* ------------------------------------------------------------------ */
/* Catálogo en memoria                                                 */
/* ------------------------------------------------------------------ */

/* El índice completo se lee de una vez y se trocea in situ sustituyendo los
 * tabuladores por ceros: los campos apuntan dentro de ese único bloque, así
 * que no hay una reserva de memoria por paquete. */
typedef struct {
    const char *nombre;
    const char *repo;
    const char *archivo;
    const char *sha;
    long long   csize;     /* bytes que ocupa la descarga */
    long long   isize;     /* bytes que ocupa una vez instalado */
    const char *deps;      /* "a,b,c" o "" */
    const char *desc;      /* para poder buscar por lo que hace, no sólo por
                            * el nombre: "minecraft" encuentra prismlauncher */
} Paquete;

typedef struct {
    const char *virtual;
    const char *real;
} Provee;

static char    *catalogo;          /* contenido crudo de index.tsv */
static Paquete *paquetes;
static int      n_paquetes;
static Provee  *provees;
static int      n_provees;

/* Tablas hash de nombre -> posición, con direccionamiento abierto. */
static int hash_pkg[HASH_SIZE];
static int hash_prov[HASH_SIZE];

static unsigned long djb2(const char *s) {
    unsigned long h = 5381;
    while (*s) h = ((h << 5) + h) + (unsigned char)*s++;
    return h;
}

static void hash_insertar(int *tabla, const char *clave, int valor,
                          const char *(*obtener)(int)) {
    unsigned long i = djb2(clave) & (HASH_SIZE - 1);
    while (tabla[i] != -1) {
        if (strcmp(obtener(tabla[i]), clave) == 0) return;  /* primero gana */
        i = (i + 1) & (HASH_SIZE - 1);
    }
    tabla[i] = valor;
}

static int hash_buscar(const int *tabla, const char *clave,
                       const char *(*obtener)(int)) {
    unsigned long i = djb2(clave) & (HASH_SIZE - 1);
    while (tabla[i] != -1) {
        if (strcmp(obtener(tabla[i]), clave) == 0) return tabla[i];
        i = (i + 1) & (HASH_SIZE - 1);
    }
    return -1;
}

static const char *nombre_pkg(int i)  { return paquetes[i].nombre; }
static const char *nombre_prov(int i) { return provees[i].virtual; }

static int run(const char *fmt, ...) {
    char cmd[4096];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(cmd, sizeof(cmd), fmt, ap);
    va_end(ap);
    return system(cmd);
}

/* Trocea una línea por tabuladores. Devuelve cuántos campos encontró. */
static int trocear(char *linea, char **campos, int max) {
    int n = 0;
    campos[n++] = linea;
    for (char *p = linea; *p && n < max; p++) {
        if (*p == '\t') { *p = 0; campos[n++] = p + 1; }
    }
    return n;
}

static int cargar_catalogo(void) {
    const char *ruta_indice = getenv("MPM_INDEX");
    if (!ruta_indice || !*ruta_indice) ruta_indice = INDICE_DEF;
    FILE *f = fopen(ruta_indice, "rb");
    if (!f) return 0;

    fseek(f, 0, SEEK_END);
    long tam = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (tam <= 0) { fclose(f); return 0; }

    catalogo = malloc((size_t)tam + 1);
    if (!catalogo) { fclose(f); return 0; }
    size_t leidos = fread(catalogo, 1, (size_t)tam, f);
    fclose(f);
    catalogo[leidos] = 0;

    /* Una pasada para contar y así reservar el tamaño exacto. */
    int np = 0, nv = 0;
    for (char *p = catalogo; *p; ) {
        if (p[0] == 'P' && p[1] == '\t') np++;
        else if (p[0] == 'V' && p[1] == '\t') nv++;
        char *nl = strchr(p, '\n');
        if (!nl) break;
        p = nl + 1;
    }
    paquetes = calloc((size_t)np + 1, sizeof(Paquete));
    provees  = calloc((size_t)nv + 1, sizeof(Provee));
    if (!paquetes || !provees) return 0;

    for (int i = 0; i < HASH_SIZE; i++) { hash_pkg[i] = -1; hash_prov[i] = -1; }

    char *p = catalogo;
    while (*p) {
        char *nl = strchr(p, '\n');
        if (nl) *nl = 0;
        char *campos[12];
        int n = trocear(p, campos, 12);
        if (n >= 8 && campos[0][0] == 'P') {
            paquetes[n_paquetes].nombre  = campos[1];
            paquetes[n_paquetes].repo    = campos[2];
            paquetes[n_paquetes].archivo = campos[3];
            paquetes[n_paquetes].sha     = campos[4];
            paquetes[n_paquetes].csize   = atoll(campos[5]);
            paquetes[n_paquetes].isize   = atoll(campos[6]);
            paquetes[n_paquetes].deps    = campos[7];
            paquetes[n_paquetes].desc    = (n >= 9) ? campos[8] : "";
            n_paquetes++;
        } else if (n >= 3 && campos[0][0] == 'V') {
            provees[n_provees].virtual = campos[1];
            provees[n_provees].real    = campos[2];
            n_provees++;
        }
        if (!nl) break;
        p = nl + 1;
    }

    for (int i = 0; i < n_paquetes; i++)
        hash_insertar(hash_pkg, paquetes[i].nombre, i, nombre_pkg);
    for (int i = 0; i < n_provees; i++)
        hash_insertar(hash_prov, provees[i].virtual, i, nombre_prov);

    return n_paquetes > 0;
}

/* ------------------------------------------------------------------ */
/* Resolución                                                          */
/* ------------------------------------------------------------------ */

static int es_base(const char *pkg) {
    for (int i = 0; PKG_BASE[i]; i++)
        if (strcmp(PKG_BASE[i], pkg) == 0) return 1;
    return 0;
}

static int esta_registrado(const char *pkg) {
    char ruta[320];
    struct stat st;
    snprintf(ruta, sizeof(ruta), "/var/lib/mpm/installed/%s.json", pkg);
    return stat(ruta, &st) == 0;
}

/* Traduce un nombre a paquete real. Devuelve el índice en paquetes[] o -1.
 * Si el nombre es virtual busca quién lo provee, dando prioridad a la tabla
 * PREFERIDOS para que la elección sea siempre la misma y tenga sentido. */
static int resolver_nombre(const char *nombre) {
    int i = hash_buscar(hash_pkg, nombre, nombre_pkg);
    if (i >= 0) return i;

    for (int k = 0; PREFERIDOS[k][0]; k++) {
        if (strcmp(PREFERIDOS[k][0], nombre) == 0) {
            int j = hash_buscar(hash_pkg, PREFERIDOS[k][1], nombre_pkg);
            if (j >= 0) return j;
            break;
        }
    }

    int v = hash_buscar(hash_prov, nombre, nombre_prov);
    if (v >= 0) return hash_buscar(hash_pkg, provees[v].real, nombre_pkg);
    return -1;
}

/* Cola de la búsqueda en anchura: el paquete pedido va primero y sus
 * dependencias detrás, así que recorrerla al revés instala siempre las hojas
 * antes que quien las necesita. */
static int  cola[MAX_COLA];
static int  n_cola;
/* Dependencias que ya estaban en el sistema. Se cuentan para poder decirlo en
 * el plan: no es lo mismo "no hace falta" que "se me ha olvidado". */
static int  n_ya_instalados;
static char visitado[1 << 20];     /* por índice de paquete */

static void encolar(int idx) {
    if (idx < 0 || n_cola >= MAX_COLA) return;
    if (visitado[idx]) return;
    visitado[idx] = 1;
    cola[n_cola++] = idx;
}

/* Limpia una entrada de %DEPENDS%: quita restricción de versión y descripción
 * ("gtk3>=3.24", "python: para los plugins"). */
static void limpiar_dep(const char *cruda, char *salida, size_t tam) {
    size_t j = 0;
    for (size_t i = 0; cruda[i] && j + 1 < tam; i++) {
        char c = cruda[i];
        if (c == '>' || c == '<' || c == '=' || c == ':' || c == ' ') break;
        salida[j++] = c;
    }
    salida[j] = 0;
}

static int buscar(const char *texto, int tope);

static void resolver(const char *raiz) {
    int r = resolver_nombre(raiz);
    if (r < 0) {
        printf("No hay ningún paquete que se llame '%s'.\n", raiz);
        printf("\nQuizá buscabas alguno de estos:\n");
        if (buscar(raiz, 10) == 0)
            printf("  (nada parecido en core/extra)\n");
        printf("\nInstala con: mpm install <nombre>\n");
        exit(1);
    }
    encolar(r);

    /* La cola crece mientras se recorre: cada paquete añade sus dependencias
     * al final y se procesan en el mismo bucle. Sin límite de profundidad --
     * el que había (4 niveles) cortaba cadenas largas y dejaba justo los
     * "cannot open shared object file" que esto viene a arreglar. */
    for (int i = 0; i < n_cola; i++) {
        const char *deps = paquetes[cola[i]].deps;
        if (!deps || !*deps) continue;

        char buf[128];
        const char *ini = deps;
        while (*ini) {
            const char *fin = strchr(ini, ',');
            size_t len = fin ? (size_t)(fin - ini) : strlen(ini);
            if (len > 0 && len < sizeof(buf)) {
                char cruda[128];
                memcpy(cruda, ini, len);
                cruda[len] = 0;
                limpiar_dep(cruda, buf, sizeof(buf));
                if (buf[0] && !es_base(buf)) {
                    if (esta_registrado(buf)) {
                        n_ya_instalados++;
                    } else {
                        int d = resolver_nombre(buf);
                        if (d < 0)
                            fprintf(stderr, "  aviso: '%s' no está en el catálogo, se omite\n", buf);
                        else if (es_base(paquetes[d].nombre))
                            ;   /* parte del sistema base: nunca se toca */
                        else if (esta_registrado(paquetes[d].nombre))
                            n_ya_instalados++;
                        else
                            encolar(d);
                    }
                }
            }
            if (!fin) break;
            ini = fin + 1;
        }
    }
}


/* ------------------------------------------------------------------ */
/* Búsqueda y sugerencias                                              */
/* ------------------------------------------------------------------ */

/* Comparación sin distinguir mayúsculas, sin depender de la localización. */
static int contiene(const char *heno, const char *aguja) {
    if (!heno || !aguja || !*aguja) return 0;
    size_t la = strlen(aguja);
    for (const char *p = heno; *p; p++) {
        size_t i = 0;
        while (i < la) {
            char a = p[i], b = aguja[i];
            if (a >= 'A' && a <= 'Z') a += 32;
            if (b >= 'A' && b <= 'Z') b += 32;
            if (a != b) break;
            i++;
        }
        if (i == la) return 1;
    }
    return 0;
}

/* Cuántos caracteres iniciales comparten dos nombres. Es lo que permite que
 * "chrome" lleve a "chromium" sin mantener a mano una lista de equivalencias
 * que siempre estaría incompleta. */
static int prefijo_comun(const char *a, const char *b) {
    int n = 0;
    while (a[n] && b[n]) {
        char x = a[n], y = b[n];
        if (x >= 'A' && x <= 'Z') x += 32;
        if (y >= 'A' && y <= 'Z') y += 32;
        if (x != y) break;
        n++;
    }
    return n;
}

typedef struct { int idx; int puntos; } Candidato;

static int cmp_candidato(const void *a, const void *b) {
    const Candidato *x = a, *y = b;
    if (x->puntos != y->puntos) return y->puntos - x->puntos;
    return strcmp(paquetes[x->idx].nombre, paquetes[y->idx].nombre);
}

/* Busca en el catálogo y devuelve cuántos resultados imprimió.
 *
 * El orden importa más que la cantidad: quien escribe "chrome" quiere ver
 * "chromium" arriba del todo, no enterrado entre cuarenta paquetes que
 * mencionan la palabra en su descripción.
 */
static int buscar(const char *texto, int tope) {
    size_t largo = strlen(texto);
    Candidato *cands = malloc((size_t)n_paquetes * sizeof(Candidato));
    if (!cands) return 0;
    int n = 0;

    for (int i = 0; i < n_paquetes; i++) {
        const char *nom = paquetes[i].nombre;
        int puntos = 0;

        int pref = prefijo_comun(nom, texto);

        if (strcmp(nom, texto) == 0) {
            puntos = 1000;
        } else if (pref >= 4 && largo >= 4) {
            /* El prefijo compartido pesa mucho más que la longitud del
             * nombre. Con el reparto anterior, "chrome" ponía "chrony" y
             * "chrono" por delante de "chromium" sólo por ser más cortos. */
            puntos = 100 + pref * 10 - (int)strlen(nom);
        } else if (contiene(nom, texto)) {
            /* El nombre lleva la palabra dentro pero no empieza por ella:
             * "chromecast" contiene "chrome" y casi nunca es lo que se
             * busca, así que un nombre largo baja deprisa. */
            puntos = 90 - (int)strlen(nom) * 2;
        } else if (largo >= 5 && strlen(nom) >= 4 &&
                   strncmp(nom, texto, strlen(nom)) == 0) {
            /* Lo escrito empieza por el nombre de un paquete real
             * ("chromium-dev" -> "chromium"). Sólo vale al principio: sin
             * eso, "minecraft" acababa sugiriendo "raft". */
            puntos = 80 - (int)strlen(nom);
        } else if (contiene(paquetes[i].desc, texto)) {
            puntos = 30;
        }

        if (puntos < 1) puntos = 0;

        if (puntos > 0) { cands[n].idx = i; cands[n].puntos = puntos; n++; }
    }

    qsort(cands, (size_t)n, sizeof(Candidato), cmp_candidato);

    int mostrados = n < tope ? n : tope;
    for (int i = 0; i < mostrados; i++) {
        Paquete *p = &paquetes[cands[i].idx];
        /* Sin sangría y sin recortar a 60: la sangría descuadraba la tabla
         * que monta mpm, y el recorte partía las descripciones a mitad de
         * palabra ("...search in PDFs, E-Books, Office docum"). Si hay que
         * cortar, que lo haga la terminal por su ancho real. */
        printf("%s %s %s\n", p->nombre, p->repo, p->desc ? p->desc : "");
    }
    if (n > mostrados)
        printf("  ... y %d más. Afina la búsqueda o usa 'mpm search'.\n", n - mostrados);

    free(cands);
    return n;
}

/* ------------------------------------------------------------------ */
/* Descarga e instalación                                              */
/* ------------------------------------------------------------------ */

static const char *espejo(void) {
    const char *e = getenv("MPM_MIRROR");
    return (e && *e) ? e : ESPEJO_DEF;
}

/* Tamaños legibles. El catálogo los da en bytes y nadie sabe de un vistazo
 * si 88514864 son muchos o pocos. */
static void formato_tam(long long bytes, char *salida, size_t tam) {
    if (bytes <= 0)                 snprintf(salida, tam, "-");
    else if (bytes < 1024LL*1024)   snprintf(salida, tam, "%.1f KB", bytes / 1024.0);
    else if (bytes < 1024LL*1024*1024) snprintf(salida, tam, "%.1f MB", bytes / (1024.0*1024));
    else                            snprintf(salida, tam, "%.2f GB", bytes / (1024.0*1024*1024));
}

/* Ordena la lista por tamaño de descarga descendente para enseñarla: con
 * doscientas dependencias, lo primero que quiere ver quien decide si acepta
 * son las cuatro que se llevan la mitad de los megabytes. */
static int cmp_por_tam(const void *a, const void *b) {
    long long ca = paquetes[*(const int *)a].csize;
    long long cb = paquetes[*(const int *)b].csize;
    return (cb > ca) - (cb < ca);
}

/* Pregunta al usuario. Por omisión sí: es la respuesta que se da casi
 * siempre y así basta con pulsar Intro. */
static int confirmar(void) {
    printf("\n¿Continuar? [S/n] ");
    fflush(stdout);
    int c = getchar();
    if (c == EOF || c == '\n') return 1;
    /* Consumir el resto de la línea para no dejar basura en la entrada. */
    int r = (c == 's' || c == 'S' || c == 'y' || c == 'Y');
    int d;
    while ((d = getchar()) != '\n' && d != EOF) { }
    return r;
}

int main(int argc, char **argv) {
    int simular = 0;
    int sin_preguntar = 0;
    int modo_buscar = 0;
    char *pedidos[32];
    int n_pedidos = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--simular") == 0 || strcmp(argv[i], "-s") == 0)
            simular = 1;
        else if (strcmp(argv[i], "--si") == 0 || strcmp(argv[i], "-y") == 0)
            sin_preguntar = 1;
        else if (strcmp(argv[i], "--buscar") == 0)
            modo_buscar = 1;
        else if (n_pedidos < 32)
            pedidos[n_pedidos++] = argv[i];
    }
    if (n_pedidos == 0) {
        fprintf(stderr, "Uso: mpm install [-y] <paquete>\n"
                        "  --simular  muestra el plan y no toca nada\n"
                        "  --si       no pide confirmación\n"
                        "  --buscar   busca en el catálogo en vez de instalar\n");
        return 1;
    }

    /* Instalar escribe en / y en /var/lib/mpm: sin esto, ejecutarlo como
     * usuario normal moría con "Permission denied" y había que acordarse de
     * anteponer sudo a mano. */
    if (geteuid() != 0 && !simular && !modo_buscar) {
        if (system("command -v m-sudo >/dev/null 2>&1") == 0) {
            char *args[32];
            int n = 0;
            args[n++] = "m-sudo";
            args[n++] = "/usr/lib/mpm/resolver";
            for (int i = 1; i < argc && n < 30; i++) args[n++] = argv[i];
            args[n] = NULL;
            execvp("m-sudo", args);
        }
        fprintf(stderr, "mpm: hacen falta permisos de root.\n");
        return 1;
    }

    if (!simular && !modo_buscar)
        run("mkdir -p /var/lib/mpm/tmp /var/lib/mpm/installed /var/lib/mpm/sync");

    if (((!simular && !modo_buscar) && run(SYNC " --si-hace-falta") != 0) || !cargar_catalogo()) {
        fprintf(stderr, "mpm: no hay catálogo de paquetes. "
                        "Ejecuta 'mpm sync' para descargarlo.\n");
        return 1;
    }

    if (modo_buscar) {
        for (int i = 0; i < n_pedidos; i++) {
            if (buscar(pedidos[i], 25) == 0)
                printf("  (nada que coincida con '%s')\n", pedidos[i]);
        }
        return 0;
    }

    for (int i = 0; i < n_pedidos; i++) resolver(pedidos[i]);

    if (n_cola == 0) {
        printf("Nada que hacer: %s y sus dependencias ya están instalados.\n", pedidos[0]);
        return 0;
    }

    /* El plan se calcula entero y se enseña de una vez. Nada de ir
     * descubriendo dependencias mientras ya se está instalando: quien acepta
     * tiene que poder ver antes cuánto se va a descargar y cuánto va a ocupar. */
    long long total_descarga = 0, total_instalado = 0;
    for (int i = 0; i < n_cola; i++) {
        total_descarga  += paquetes[cola[i]].csize;
        total_instalado += paquetes[cola[i]].isize;
    }

    /* Copia para enseñar: la cola original conserva el orden de instalación. */
    int *muestra = malloc((size_t)n_cola * sizeof(int));
    if (!muestra) { fprintf(stderr, "mpm: sin memoria.\n"); return 1; }
    memcpy(muestra, cola, (size_t)n_cola * sizeof(int));
    qsort(muestra, (size_t)n_cola, sizeof(int), cmp_por_tam);

    char t1[32], t2[32];
    printf("\n%s\n", pedidos[0]);
    if (n_cola > 1) printf("\nDependencias nuevas (%d):\n", n_cola - 1);
    for (int i = 0; i < n_cola; i++) {
        Paquete *p = &paquetes[muestra[i]];
        if (strcmp(p->nombre, pedidos[0]) == 0) continue;
        formato_tam(p->csize, t1, sizeof(t1));
        printf("  %-32s %10s\n", p->nombre, t1);
    }
    free(muestra);

    formato_tam(total_descarga, t1, sizeof(t1));
    formato_tam(total_instalado, t2, sizeof(t2));
    printf("\n  %-26s %10d\n", "Paquetes nuevos:", n_cola);
    printf("  %-26s %10s\n", "Descarga total:", t1);
    printf("  %-26s %10s\n", "Espacio adicional en disco:", t2);
    if (n_ya_instalados)
        printf("  %-26s %10d\n", "Ya instalados (se omiten):", n_ya_instalados);

    /* Espacio libre. Descargar 320 MB y descomprimir 1,3 GB en un disco que
     * no da para tanto acaba con el sistema a medio instalar y sin sitio ni
     * para arrancar. Se comprueba antes de tocar la red. */
    struct statvfs disco;
    if (statvfs("/var/lib/mpm", &disco) == 0) {
        long long libre = (long long)disco.f_bavail * (long long)disco.f_frsize;
        /* Los paquetes descargados se borran al terminar, pero mientras dura
         * la instalación conviven con lo ya extraído. Se pide la suma más un
         * margen de 200 MB para no dejar el disco al borde. */
        long long necesario = total_descarga + total_instalado + 200LL*1024*1024;
        if (libre < necesario) {
            formato_tam(libre, t1, sizeof(t1));
            formato_tam(necesario, t2, sizeof(t2));
            fprintf(stderr, "\nmpm: no hay espacio suficiente. "
                            "Libre: %s, hacen falta %s.\n", t1, t2);
            return 1;
        }
    }

    if (simular) return 0;

    if (!sin_preguntar && !confirmar()) {
        printf("Cancelado.\n");
        return 1;
    }

    printf("\nDescargando %d paquete(s)...\n", n_cola);

    char work[] = "/var/lib/mpm/tmp/arch_XXXXXX";
    char *workdir = mkdtemp(work);
    if (!workdir) { perror("mpm: mkdtemp"); return 1; }

    /* Una sola llamada a curl para todo, con -Z para que vayan en paralelo.
     * La lista va en un archivo de configuración y no en la línea de órdenes:
     * con doscientos paquetes la línea se pasaría de largo. */
    char ruta[512];
    snprintf(ruta, sizeof(ruta), "%s/descargas.curl", workdir);
    FILE *cfg = fopen(ruta, "w");
    snprintf(ruta, sizeof(ruta), "%s/sumas.sha256", workdir);
    FILE *sumas = fopen(ruta, "w");
    if (!cfg || !sumas) {
        fprintf(stderr, "mpm: no se pudo preparar la descarga.\n");
        run("rm -rf '%s'", workdir);
        return 1;
    }
    for (int i = 0; i < n_cola; i++) {
        Paquete *p = &paquetes[cola[i]];
        fprintf(cfg, "url = \"%s/%s/os/x86_64/%s\"\noutput = \"%s/%s\"\n",
                espejo(), p->repo, p->archivo, workdir, p->archivo);
        if (p->sha && *p->sha)
            fprintf(sumas, "%s  %s/%s\n", p->sha, workdir, p->archivo);
    }
    fclose(cfg);
    fclose(sumas);

    if (run("curl -fsSL -Z --parallel-max 8 --retry 3 --connect-timeout 15 "
            "-K '%s/descargas.curl'", workdir) != 0) {
        fprintf(stderr, "mpm: fallo al descargar los paquetes.\n");
        run("rm -rf '%s'", workdir);
        return 1;
    }

    /* El catálogo publica el SHA256 de cada paquete: comprobarlo cuesta un
     * segundo y descarta descargas cortadas o un espejo manipulado. */
    printf("Verificando integridad... ");
    fflush(stdout);
    if (run("sha256sum -c '%s/sumas.sha256' >/dev/null 2>&1", workdir) != 0) {
        printf("FALLO\n");
        fprintf(stderr, "mpm: algún paquete no coincide con su "
                        "SHA256 publicado. No se instala nada.\n");
        run("rm -rf '%s'", workdir);
        return 1;
    }
    printf("ok\n");

    /* Al revés: las hojas primero, el paquete pedido al final. */
    int fallos = 0;
    for (int i = n_cola - 1; i >= 0; i--) {
        Paquete *p = &paquetes[cola[i]];
        char destino[600];
        snprintf(destino, sizeof(destino), "%s/root", workdir);
        run("rm -rf '%s' && mkdir -p '%s'", destino, destino);

        if (run("zstd -dc '%s/%s' 2>/dev/null | tar -x -C '%s'",
                workdir, p->archivo, destino) != 0) {
            fprintf(stderr, "  fallo al extraer %s\n", p->archivo);
            fallos++;
            continue;
        }

        /* Metadatos de pacman (.PKGINFO, .BUILDINFO, .MTREE, .INSTALL) no van
         * al sistema real -- sólo el contenido del paquete. */
        run("rm -f '%s'/.PKGINFO '%s'/.BUILDINFO '%s'/.MTREE '%s'/.INSTALL",
            destino, destino, destino, destino);
        run("cp -a '%s'/. / 2>/dev/null", destino);

        snprintf(ruta, sizeof(ruta), "/var/lib/mpm/installed/%s.json", p->nombre);
        FILE *reg = fopen(ruta, "w");
        if (reg) {
            fprintf(reg, "{\"name\":\"%s\",\"version\":\"arch-repo\","
                         "\"category\":\"arch\",\"origin\":\"%s/%s\"}\n",
                    p->nombre, espejo(), p->repo);
            fclose(reg);
        }
        printf("  [%d/%d] %s\n", n_cola - i, n_cola, p->nombre);
    }

    run("rm -rf '%s'", workdir);

    /* Las fuentes recién instaladas no las ve nadie hasta que se reconstruye
     * la caché de fontconfig: es la diferencia entre Firefox con texto y
     * Firefox con ventanas en blanco. */
    run("command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1");
    run("command -v gtk-update-icon-cache >/dev/null 2>&1 && "
        "gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null");
    run("command -v ldconfig >/dev/null 2>&1 && ldconfig 2>/dev/null");

    if (fallos) {
        fprintf(stderr, "[!] %d paquete(s) fallaron al instalarse.\n", fallos);
        return 1;
    }
    printf("[OK] %s instalado con %d dependencia(s).\n", pedidos[0], n_cola - 1);
    return 0;
}
