/*
 * m-colores - saca la paleta del sistema de una imagen.
 *
 * Le das un fondo de pantalla y te devuelve los colores con los que se pinta
 * TODO: la barra, el Centro de Control, los bordes de ventana y la terminal.
 * La idea es que el escritorio se vea de una pieza con el fondo en vez de un
 * cian fijo encima de la foto que sea.
 *
 * Por qué en C y con GdkPixbuf:
 *   MIKE OS no lleva Python ni ImageMagick, y no va a llevarlos por esto.
 *   GdkPixbuf ya está dentro -- lo usa la ventana de bienvenida y el selector
 *   de fondos -- y sabe leer PNG, JPEG y el resto sin añadir nada nuevo.
 *
 * Cómo elige:
 *   La imagen se carga reducida a 120 px de ancho: para sacar un color
 *   dominante sobran los dos millones de píxeles del original, y así tarda
 *   milisegundos. Cada píxel vota por su tono, y el voto pesa más cuanto más
 *   vivo es el color y más cerca está de un brillo medio. Los grises casi no
 *   votan, que es lo correcto: el tono de un gris no significa nada.
 *
 * Lo importante, y la razón de que esto no sea un simple "coge el color más
 * frecuente": el resultado TIENE QUE LEERSE. Un fondo oscuro daría un acento
 * negro sobre negro, y uno pastel daría un texto ilegible. Así que del fondo
 * se toma sólo el TONO; la saturación y el brillo de cada papel se fijan aquí
 * dentro, en valores que ya sabemos que contrastan. El escritorio cambia de
 * color, no de legibilidad.
 *
 *   m-colores <imagen>            imprime CLAVE=valor
 *   m-colores --aplicar <imagen>  además lo guarda en los ajustes
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <gdk-pixbuf/gdk-pixbuf.h>

#define TONOS 36          /* cubos de 10 grados */
#define ANCHO_ANALISIS 120

static void rgb_a_hsl(double r, double g, double b,
                      double *h, double *s, double *l) {
    double mx = fmax(r, fmax(g, b));
    double mn = fmin(r, fmin(g, b));
    double d = mx - mn;
    *l = (mx + mn) / 2.0;

    if (d < 1e-9) { *h = 0; *s = 0; return; }

    *s = (*l > 0.5) ? d / (2.0 - mx - mn) : d / (mx + mn);

    if (mx == r)      *h = 60.0 * fmod(((g - b) / d), 6.0);
    else if (mx == g) *h = 60.0 * (((b - r) / d) + 2.0);
    else              *h = 60.0 * (((r - g) / d) + 4.0);

    if (*h < 0) *h += 360.0;
}

static double canal(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

static void hsl_a_hex(double h, double s, double l, char *salida) {
    double r, g, b;
    if (s < 1e-9) {
        r = g = b = l;
    } else {
        double q = (l < 0.5) ? l * (1 + s) : l + s - l * s;
        double p = 2 * l - q;
        double hn = h / 360.0;
        r = canal(p, q, hn + 1.0 / 3.0);
        g = canal(p, q, hn);
        b = canal(p, q, hn - 1.0 / 3.0);
    }
    snprintf(salida, 8, "#%02x%02x%02x",
             (int)(fmin(1.0, fmax(0.0, r)) * 255 + 0.5),
             (int)(fmin(1.0, fmax(0.0, g)) * 255 + 0.5),
             (int)(fmin(1.0, fmax(0.0, b)) * 255 + 0.5));
}

int main(int argc, char **argv) {
    const char *ruta = NULL;
    int aplicar = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--aplicar") == 0) aplicar = 1;
        else if (argv[i][0] != '-') ruta = argv[i];
    }
    if (!ruta) {
        fprintf(stderr, "Uso: m-colores [--aplicar] <imagen>\n");
        return 1;
    }

    GError *err = NULL;
    /* Se pide ya reducida: decodificar el original entero para mirar un color
     * dominante es tirar tiempo y memoria. -1 en el alto conserva la
     * proporción. */
    GdkPixbuf *img = gdk_pixbuf_new_from_file_at_scale(ruta, ANCHO_ANALISIS, -1,
                                                       TRUE, &err);
    if (!img) {
        fprintf(stderr, "m-colores: no se puede leer %s: %s\n",
                ruta, err ? err->message : "motivo desconocido");
        return 1;
    }

    int w = gdk_pixbuf_get_width(img);
    int h = gdk_pixbuf_get_height(img);
    int canales = gdk_pixbuf_get_n_channels(img);
    int paso = gdk_pixbuf_get_rowstride(img);
    guchar *px = gdk_pixbuf_get_pixels(img);

    double peso[TONOS];
    double suma_sat[TONOS];
    for (int i = 0; i < TONOS; i++) { peso[i] = 0; suma_sat[i] = 0; }

    double sat_media = 0;
    long contados = 0;

    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            guchar *p = px + y * paso + x * canales;
            /* Un píxel transparente no aporta color a nada. */
            if (canales == 4 && p[3] < 128) continue;

            double r = p[0] / 255.0, g = p[1] / 255.0, b = p[2] / 255.0;
            double hh, ss, ll;
            rgb_a_hsl(r, g, b, &hh, &ss, &ll);

            sat_media += ss;
            contados++;

            /* Un gris no tiene tono que aportar: su "h" es ruido. Y un píxel
             * casi negro o casi blanco tampoco dice de qué color es la
             * imagen. */
            if (ss < 0.12) continue;
            if (ll < 0.06 || ll > 0.94) continue;

            /* Pesa la viveza y la cercanía a un brillo medio: los colores del
             * medio del rango son los que una persona diría que "son" el
             * color de la foto. */
            double cercania = 1.0 - fabs(ll - 0.5) * 2.0;
            double v = ss * ss * (0.35 + 0.65 * cercania);

            int cubo = (int)(hh / (360.0 / TONOS));
            if (cubo < 0) cubo = 0;
            if (cubo >= TONOS) cubo = TONOS - 1;
            peso[cubo] += v;
            suma_sat[cubo] += ss;
        }
    }
    if (contados > 0) sat_media /= contados;

    /* El tono ganador, suavizado con sus vecinos: si la imagen tiene un
     * degradado, el color reparte votos entre cubos contiguos y sin esto
     * ganaría un cubo cualquiera por casualidad. */
    int mejor = 0;
    double mejor_v = -1;
    for (int i = 0; i < TONOS; i++) {
        double v = peso[i]
                 + 0.5 * peso[(i + 1) % TONOS]
                 + 0.5 * peso[(i + TONOS - 1) % TONOS];
        if (v > mejor_v) { mejor_v = v; mejor = i; }
    }

    double tono = (mejor + 0.5) * (360.0 / TONOS);

    /* Una imagen en blanco y negro no tiene tono que copiar. En vez de
     * inventarse uno, se queda el cian de MIKE OS: es lo que esperaría
     * cualquiera que pone un fondo gris. */
    int sin_color = (mejor_v < 1e-6) || (sat_media < 0.035);
    if (sin_color) tono = 190.0;

    /*
     * Y aquí está lo que hace que esto se pueda usar de verdad: del fondo se
     * toma SÓLO el tono. Saturación y brillo son fijos, elegidos para que el
     * texto contraste siempre. Sin esto, un fondo oscuro daría un acento
     * negro sobre negro y uno pastel un texto ilegible; y quien lo pusiera no
     * podría ni volver a los ajustes para deshacerlo, porque no vería nada.
     */
    char acento[8], fondo[8], superficie[8], superficie_alta[8];
    char borde[8], texto[8], texto_tenue[8], sobre_acento[8];

    hsl_a_hex(tono, 0.92, 0.58, acento);
    hsl_a_hex(tono, 0.24, 0.045, fondo);
    hsl_a_hex(tono, 0.19, 0.085, superficie);
    hsl_a_hex(tono, 0.17, 0.125, superficie_alta);
    hsl_a_hex(tono, 0.15, 0.185, borde);
    hsl_a_hex(tono, 0.07, 0.925, texto);
    hsl_a_hex(tono, 0.09, 0.555, texto_tenue);
    hsl_a_hex(tono, 0.45, 0.04, sobre_acento);

    printf("accent_color=%s\n", acento);
    printf("color_fondo=%s\n", fondo);
    printf("color_superficie=%s\n", superficie);
    printf("color_superficie_alta=%s\n", superficie_alta);
    printf("color_borde=%s\n", borde);
    printf("color_texto=%s\n", texto);
    printf("color_texto_tenue=%s\n", texto_tenue);
    printf("color_sobre_acento=%s\n", sobre_acento);
    printf("color_origen=%s\n", sin_color ? "defecto" : "fondo");

    g_object_unref(img);

    if (aplicar) {
        /* Se delega en m-apply-settings en vez de escribir el JSON aquí: es
         * quien sabe validar cada clave y quien reescribe el archivo de forma
         * atómica. Dos sitios escribiendo los mismos ajustes acabarían
         * pisándose. */
        char orden[2048];
        snprintf(orden, sizeof(orden),
                 "m-apply-settings set accent_color=%s color_fondo=%s "
                 "color_superficie=%s color_superficie_alta=%s color_borde=%s "
                 "color_texto=%s color_texto_tenue=%s color_sobre_acento=%s "
                 "colores_del_fondo=si >/dev/null 2>&1",
                 acento, fondo, superficie, superficie_alta, borde,
                 texto, texto_tenue, sobre_acento);
        if (system(orden) != 0) {
            fprintf(stderr, "m-colores: no se han podido guardar los ajustes.\n");
            return 1;
        }
    }
    return 0;
}
