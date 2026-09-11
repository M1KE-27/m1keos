/*
 * m-welcome - Panel de bienvenida de MIKE OS.
 *
 * Se lanza una vez por exec-once en hyprland.conf. Si ya existe
 * ~/.config/mike/.welcomed sale al instante (no-op en arranques
 * posteriores); si no, muestra un panel casi a pantalla completa con
 * todos los controles del sistema y crea el flag al cerrarse para no
 * volver a aparecer.
 */
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>

static char *flag_path(void) {
    return g_strdup_printf("%s/.config/mike/.welcomed", g_get_home_dir());
}

static void mark_welcomed(void) {
    char *path = flag_path();
    FILE *f = fopen(path, "w");
    if (f) fclose(f);
    g_free(path);
}

static void on_close(GtkWidget *widget, gpointer data) {
    (void)widget; (void)data;
    mark_welcomed();
    gtk_main_quit();
}

typedef struct { const char *keys; const char *desc; } Bind;

typedef struct { const char *title; const Bind *binds; guint count; } Section;

static const Bind TERMINAL[] = {
    { "SUPER/ALT + Return", "Abrir terminal" },
    { "CTRL + ALT + T",     "Abrir terminal (alternativo)" },
};

static const Bind APPS[] = {
    { "SUPER/ALT + Space",  "Lanzador rápido (fuzzel)" },
    { "SUPER + D",          "Lanzador alternativo" },
    { "SUPER + W",          "Fondos de pantalla (Wallhaven, en vivo)" },
    { "SUPER + N",          "Estado de red" },
    { "SUPER + I",          "Información del sistema" },
};

static const Bind WINDOWS[] = {
    { "SUPER/ALT + Q",      "Cerrar ventana activa" },
    { "SUPER/ALT + F",      "Pantalla completa" },
    { "SUPER/ALT + V",      "Alternar flotante" },
    { "SUPER/ALT + ←↑↓→",   "Mover el foco" },
    { "SUPER/ALT + arrastrar", "Mover / redimensionar (clic der.)" },
};

static const Bind WORKSPACES[] = {
    { "SUPER/ALT + 1..4",       "Cambiar de workspace" },
    { "SUPER/ALT + SHIFT + 1..4", "Enviar ventana al workspace" },
    { "SUPER + rueda del ratón", "Ciclar entre workspaces" },
};

static const Bind SYSTEM[] = {
    { "CTRL+ALT / ALT+SUPER + S", "Captura de pantalla" },
    { "CTRL+ALT / ALT+SUPER + ↑↓", "Subir / bajar volumen" },
    { "SUPER + F1",          "Diagnóstico del sistema" },
    { "SUPER + F2",          "Lista de servicios" },
    { "SUPER + M / F12",     "Salir de la sesión" },
};

/* Los cinco que hacen falta para empezar. El resto sigue estando, pero
 * plegado: la primera pantalla del sistema enseñaba veinticuatro atajos en
 * tres columnas y nadie lee veinticuatro atajos de golpe. */
static const Bind ESENCIALES[] = {
    { "SUPER/ALT + Return", "Abrir terminal" },
    { "SUPER/ALT + Space",  "Buscar y abrir aplicaciones" },
    { "SUPER/ALT + Q",      "Cerrar la ventana activa" },
    { "SUPER/ALT + 1..4",   "Cambiar de escritorio" },
    { "SUPER + F1",         "Diagnóstico del sistema" },
};

static const Section ESENCIAL = { "Para empezar", ESENCIALES, G_N_ELEMENTS(ESENCIALES) };

static const Section SECTIONS[] = {
    { "Terminal",       TERMINAL,   G_N_ELEMENTS(TERMINAL) },
    { "Aplicaciones",   APPS,       G_N_ELEMENTS(APPS) },
    { "Ventanas",       WINDOWS,    G_N_ELEMENTS(WINDOWS) },
    { "Workspaces",     WORKSPACES, G_N_ELEMENTS(WORKSPACES) },
    { "Sistema",        SYSTEM,     G_N_ELEMENTS(SYSTEM) },
};

static GtkWidget *build_section(const Section *sec) {
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);

    GtkWidget *h = gtk_label_new(sec->title);
    gtk_widget_set_name(h, "sechdr");
    gtk_widget_set_halign(h, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(box), h, FALSE, FALSE, 2);

    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 14);
    for (guint i = 0; i < sec->count; i++) {
        GtkWidget *k = gtk_label_new(sec->binds[i].keys);
        gtk_widget_set_name(k, "key");
        gtk_widget_set_halign(k, GTK_ALIGN_START);
        gtk_label_set_line_wrap(GTK_LABEL(k), TRUE);
        GtkWidget *d = gtk_label_new(sec->binds[i].desc);
        gtk_widget_set_name(d, "desc");
        gtk_widget_set_halign(d, GTK_ALIGN_START);
        gtk_label_set_line_wrap(GTK_LABEL(d), TRUE);
        gtk_grid_attach(GTK_GRID(grid), k, 0, (gint)i, 1, 1);
        gtk_grid_attach(GTK_GRID(grid), d, 1, (gint)i, 1, 1);
    }
    gtk_box_pack_start(GTK_BOX(box), grid, FALSE, FALSE, 0);
    return box;
}

/* Ficha del equipo: qué hay dentro y qué le falta.
 *
 * m-drivers lee los identificadores que publica el propio hardware en
 * /sys/bus/pci, así que dice la marca y el modelo reales en vez de adivinar.
 * Aquí sólo se enseña: nada se instala hasta que alguien pulsa el botón. */
static void on_instalar_drivers(GtkWidget *w, gpointer data) {
    (void)w; (void)data;
    /* En una terminal a propósito: instalar controladores descarga cientos
     * de megabytes y quien lo lanza tiene derecho a ver el progreso y los
     * errores, no una barra opaca. */
    g_spawn_command_line_async("/usr/bin/m-terminal -e \"m-drivers --instalar\"", NULL);
}

static GtkWidget *build_hardware(void) {
    GtkWidget *caja = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_widget_set_name(caja, "customizebox");
    gtk_container_set_border_width(GTK_CONTAINER(caja), 16);

    GtkWidget *tit = gtk_label_new("Tu equipo");
    gtk_widget_set_name(tit, "customizetitle");
    gtk_widget_set_halign(tit, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(caja), tit, FALSE, FALSE, 0);

    GString *detectado = g_string_new("");
    GString *recomendado = g_string_new("");
    FILE *p = popen("m-drivers 2>/dev/null", "r");
    if (p) {
        char linea[512];
        int seccion_util = 0;
        while (fgets(linea, sizeof(linea), p)) {
            linea[strcspn(linea, "\n")] = 0;
            if (g_str_has_prefix(linea, "Recomendado:")) {
                g_string_assign(recomendado, linea + 12);
                continue;
            }
            /* Los encabezados marcan de qué se habla; las líneas con dos
             * espacios de sangría son los dispositivos en sí. */
            if (linea[0] != ' ' && linea[0] != 0 && linea[0] != '=') {
                seccion_util = (g_strcmp0(linea, "Gráfica") == 0 ||
                                g_strcmp0(linea, "Red") == 0 ||
                                g_strcmp0(linea, "Procesador") == 0 ||
                                g_strcmp0(linea, "Entrada") == 0);
                continue;
            }
            if (seccion_util && g_str_has_prefix(linea, "  ") &&
                !g_str_has_prefix(linea, "    ")) {
                const char *txt = linea + 2;
                if (*txt == '(') continue;
                if (detectado->len > 0) g_string_append_c(detectado, '\n');
                /* Los nombres de las tarjetas son larguísimos; cortar por
                 * la mitad es preferible a romper la columna. */
                if (strlen(txt) > 58) {
                    g_string_append_len(detectado, txt, 55);
                    g_string_append(detectado, "...");
                } else {
                    g_string_append(detectado, txt);
                }
            }
        }
        pclose(p);
    }
    if (detectado->len == 0)
        g_string_assign(detectado, "No se pudo leer el hardware de este equipo.");

    GtkWidget *lst = gtk_label_new(detectado->str);
    gtk_widget_set_name(lst, "customizetext");
    gtk_widget_set_halign(lst, GTK_ALIGN_START);
    gtk_label_set_line_wrap(GTK_LABEL(lst), TRUE);
    gtk_label_set_max_width_chars(GTK_LABEL(lst), 40);
    gtk_box_pack_start(GTK_BOX(caja), lst, FALSE, FALSE, 0);

    if (recomendado->len > 0) {
        /* El botón de abajo dice lo que hace; no hace falta un párrafo que
         * además tranquilice sobre cuándo pulsarlo. */
        char *txt = g_strdup_printf("Faltan por instalar:%s", recomendado->str);
        GtkWidget *rec = gtk_label_new(txt);
        g_free(txt);
        gtk_widget_set_name(rec, "customizetext");
        gtk_widget_set_halign(rec, GTK_ALIGN_START);
        gtk_label_set_line_wrap(GTK_LABEL(rec), TRUE);
        gtk_label_set_max_width_chars(GTK_LABEL(rec), 40);
        gtk_box_pack_start(GTK_BOX(caja), rec, FALSE, FALSE, 6);

        GtkWidget *btn = gtk_button_new_with_label("Instalar controladores");
        gtk_widget_set_name(btn, "gobtn");
        gtk_widget_set_halign(btn, GTK_ALIGN_START);
        g_signal_connect(btn, "clicked", G_CALLBACK(on_instalar_drivers), NULL);
        gtk_box_pack_start(GTK_BOX(caja), btn, FALSE, FALSE, 6);
    } else {
        GtkWidget *ok = gtk_label_new("Nada pendiente de instalar.");
        gtk_widget_set_name(ok, "customizetext");
        gtk_widget_set_halign(ok, GTK_ALIGN_START);
        gtk_label_set_line_wrap(GTK_LABEL(ok), TRUE);
        gtk_label_set_max_width_chars(GTK_LABEL(ok), 40);
        gtk_box_pack_start(GTK_BOX(caja), ok, FALSE, FALSE, 6);
    }

    g_string_free(detectado, TRUE);
    g_string_free(recomendado, TRUE);
    return caja;
}

int main(int argc, char **argv) {
    char *path = flag_path();
    if (g_file_test(path, G_FILE_TEST_EXISTS)) {
        g_free(path);
        return 0;
    }
    g_free(path);

    gtk_init(&argc, &argv);

    GtkCssProvider *css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(css,
        /* Los mismos cinco colores que el resto del escritorio (ver
         * quickshell/Paleta.qml). El acento se reserva para el único botón
         * que hace algo: antes teñía los títulos, las teclas, los bordes y
         * las tarjetas, y todo gritaba a la vez. */
        "window { background-color: rgba(11, 13, 17, 0.92); }"
        "#title { color: #e8ebf0; font-size: 32px; font-weight: bold; }"
        "#subtitle { color: #79818f; font-size: 14px; }"
        "#sechdr { color: #79818f; font-size: 12px; font-weight: bold;"
        "  letter-spacing: 1px; }"
        "#key { color: #e8ebf0; font-family: monospace; font-weight: bold; font-size: 13px; }"
        "#desc { color: #79818f; font-size: 13px; }"
        "#gobtn { background-color: #00d4ff; color: #05070c; font-weight: bold;"
        "  font-size: 15px; border-radius: 8px; padding: 12px 26px; border: none; }"
        "#gobtn:hover { background-color: #33ddff; }"
        "#expander { color: #79818f; font-size: 13px; }"
        "#expander > label { color: #79818f; }"
        "#customizebox { background-color: #161a21;"
        "  border: 1px solid #262c36; border-radius: 10px; }"
        "#customizetitle { color: #e8ebf0; font-weight: bold; font-size: 14px; }"
        "#customizetext { color: #79818f; font-size: 13px; }",
        -1, NULL);
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "Bienvenido a MIKE OS");
    /* Tamaño relativo a la pantalla. Estaba fijo en 1728x950, que en un
     * portátil de 1366x768 se sale por los cuatro lados y deja el botón de
     * cerrar fuera de la vista. */
    {
        GdkRectangle pantalla = { 0, 0, 1280, 720 };
        GdkDisplay *disp = gdk_display_get_default();
        if (disp) {
            GdkMonitor *mon = gdk_display_get_primary_monitor(disp);
            if (!mon && gdk_display_get_n_monitors(disp) > 0)
                mon = gdk_display_get_monitor(disp, 0);
            if (mon) gdk_monitor_get_geometry(mon, &pantalla);
        }
        int an = (int)(pantalla.width  * 0.92);
        int al = (int)(pantalla.height * 0.90);
        /* Por debajo de estos tamaños el contenido no cabe de ninguna
         * manera y es mejor que la ventana desborde a que se recorte. */
        if (an < 900) an = 900;
        if (al < 560) al = 560;
        gtk_window_set_default_size(GTK_WINDOW(win), an, al);
        /* El margen interior también encoge: 48 píxeles por lado en una
         * pantalla pequeña se come el espacio útil. */
        gtk_container_set_border_width(GTK_CONTAINER(win),
                                       pantalla.height < 900 ? 20 : 48);
    }
    gtk_window_set_resizable(GTK_WINDOW(win), TRUE);
    gtk_window_set_position(GTK_WINDOW(win), GTK_WIN_POS_CENTER);
    gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
    g_signal_connect(win, "destroy", G_CALLBACK(on_close), NULL);

    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(win), outer);

    GtkWidget *title = gtk_label_new(">_ MIKE OS");
    gtk_widget_set_name(title, "title");
    gtk_widget_set_halign(title, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(outer), title, FALSE, FALSE, 0);

    GtkWidget *subtitle = gtk_label_new(
        "Bienvenido. Aquí tienes todos los controles del escritorio, resumidos.");
    gtk_widget_set_name(subtitle, "subtitle");
    gtk_widget_set_halign(subtitle, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(outer), subtitle, FALSE, FALSE, 6);

    GtkWidget *sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_box_pack_start(GTK_BOX(outer), sep, FALSE, FALSE, 18);

    /* Tres columnas de secciones para aprovechar el ancho casi-fullscreen. */
    GtkWidget *cols = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 40);
    gtk_widget_set_valign(cols, GTK_ALIGN_CENTER);
    gtk_box_pack_start(GTK_BOX(outer), cols, TRUE, FALSE, 0);

    GtkWidget *col1 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 22);
    GtkWidget *col2 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 22);
    GtkWidget *col3 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 22);
    gtk_box_pack_start(GTK_BOX(cols), col1, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(cols), col2, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(cols), col3, TRUE, TRUE, 0);

    /* Columna 1: sólo lo esencial. Columna 2: todo lo demás, plegado.
     * Columna 3: lo que hay dentro de este equipo. */
    gtk_box_pack_start(GTK_BOX(col1), build_section(&ESENCIAL), FALSE, FALSE, 0);

    GtkWidget *todos = gtk_expander_new("Ver todos los atajos");
    gtk_widget_set_name(todos, "expander");
    GtkWidget *caja_todos = gtk_box_new(GTK_ORIENTATION_VERTICAL, 18);
    for (guint i = 0; i < G_N_ELEMENTS(SECTIONS); i++)
        gtk_box_pack_start(GTK_BOX(caja_todos), build_section(&SECTIONS[i]), FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(todos), caja_todos);
    gtk_box_pack_start(GTK_BOX(col2), todos, FALSE, FALSE, 0);

    gtk_box_pack_start(GTK_BOX(col3), build_hardware(), FALSE, FALSE, 0);

    /* Aquí vivía una tarjeta que explicaba en un párrafo dónde estaba el
     * panel de control y que "no hace falta configurarlo todo ahora, puedes
     * ir cambiándolo poco a poco, cuando quieras". Una interfaz no se
     * tranquiliza a sí misma en prosa: o el botón se encuentra solo, o el
     * párrafo no lo va a arreglar. */

    GtkWidget *btnbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_halign(btnbox, GTK_ALIGN_END);
    GtkWidget *btn = gtk_button_new_with_label("Entendido, empezar");
    gtk_widget_set_name(btn, "gobtn");
    g_signal_connect(btn, "clicked", G_CALLBACK(on_close), NULL);
    gtk_box_pack_start(GTK_BOX(btnbox), btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(outer), btnbox, FALSE, FALSE, 24);

    gtk_widget_show_all(win);
    gtk_main();
    return 0;
}
