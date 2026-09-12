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

/* ¿Estamos arrancados desde el USB en vivo, o desde un disco ya instalado?
 *
 * El init monta la raíz en overlay cuando arranca en vivo; instalado, la raíz
 * es la partición de verdad. Mirar eso es más fiable que buscar el medio: un
 * USB enchufado en un equipo ya instalado también aparecería. */
static gboolean en_vivo(void) {
    gboolean vivo = FALSE;
    char *contenido = NULL;
    if (g_file_get_contents("/proc/mounts", &contenido, NULL, NULL)) {
        char **lineas = g_strsplit(contenido, "\n", -1);
        for (int i = 0; lineas[i]; i++) {
            char **campos = g_strsplit(lineas[i], " ", -1);
            if (campos[0] && campos[1] && campos[2]
                && g_strcmp0(campos[1], "/") == 0
                && g_strcmp0(campos[2], "overlay") == 0) {
                vivo = TRUE;
            }
            g_strfreev(campos);
        }
        g_strfreev(lineas);
        g_free(contenido);
    }
    return vivo;
}

/* Instalar en el disco.
 *
 * Abre el instalador gráfico. La primera versión lanzaba m-install en una
 * terminal "porque borra un disco y eso hay que verlo tal cual"; el problema
 * es que una pantalla de texto preguntando por subvolúmenes de btrfs no la
 * entiende la mayoría de la gente, y quien no la entiende no instala nada.
 * El instalador gráfico enseña lo mismo -- qué disco, qué se borra, una
 * confirmación explícita -- de forma que se pueda leer. */
static void on_instalar_sistema(GtkWidget *w, gpointer data) {
    (void)w; (void)data;
    g_spawn_command_line_async("/usr/bin/m-instalador", NULL);
}

/* Abre el Centro de Control. Sustituye al párrafo que explicaba dónde estaba:
 * si hay que explicar con palabras dónde se pulsa algo, es que falta el
 * botón. */
static void on_abrir_ajustes(GtkWidget *w, gpointer data) {
    (void)w; (void)data;
    g_spawn_command_line_async("quickshell ipc call ajustes abrir", NULL);
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
         * que hace algo. */
        "window { background-color: #0b0d11; border: 1px solid #262c36;"
        "  border-radius: 12px; }"
        "#cabecera { background-color: #0b0d11; }"
        "#title { color: #e8ebf0; font-size: 26px; font-weight: bold; }"
        "#subtitle { color: #79818f; font-size: 13px; }"
        "#raya { background-color: #262c36; min-height: 1px; }"
        /* Las tarjetas dan la estructura: sin ellas, el contenido flotaba
         * suelto sobre un fondo enorme y no se sabía qué iba con qué. */
        "#tarjeta { background-color: #161a21; border: 1px solid #262c36;"
        "  border-radius: 10px; }"
        "#tarjetatitulo { color: #e8ebf0; font-weight: bold; font-size: 14px; }"
        "#sechdr { color: #79818f; font-size: 11px; font-weight: bold;"
        "  letter-spacing: 1px; }"
        "#key { color: #e8ebf0; font-family: monospace; font-weight: bold; font-size: 12px; }"
        "#desc { color: #79818f; font-size: 12px; }"
        /* background-image: none es obligatorio. Adwaita pinta los botones
         * con un degradado, y un degradado encima tapa el color de fondo:
         * el botón principal salía gris por mucho que se le pusiera el
         * acento. Y va como "button#gobtn" para ganar en especificidad al
         * selector del tema. */
        "button#gobtn { background-color: #00d4ff; background-image: none;"
        "  color: #05070c; font-weight: bold; font-size: 14px;"
        "  border-radius: 8px; padding: 10px 26px; border: none;"
        "  text-shadow: none; box-shadow: none; }"
        "button#gobtn:hover { background-color: #33ddff; background-image: none; }"
        "button#botonsec { background-color: #1f242d; background-image: none;"
        "  color: #e8ebf0; font-size: 12px; border: 1px solid #262c36;"
        "  border-radius: 7px; padding: 7px 14px; text-shadow: none;"
        "  box-shadow: none; }"
        "button#botonsec:hover { background-color: #262c36; background-image: none; }"
        "#expander { color: #79818f; font-size: 12px; }"
        "#expander > label { color: #79818f; }"
        "#customizebox { background-color: #161a21;"
        "  border: 1px solid #262c36; border-radius: 10px; }"
        "#customizetitle { color: #e8ebf0; font-weight: bold; font-size: 14px; }"
        "#customizetext { color: #79818f; font-size: 12px; }"
        "scrolledwindow { background-color: transparent; }",
        -1, NULL);
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "Bienvenido a MIKE OS");
    /* Tamaño relativo a la pantalla. Estaba fijo en 1728x950, que en un
     * portátil de 1366x768 se sale por los cuatro lados y deja el botón de
     * cerrar fuera de la vista. */
    {
        /* Tamaño a la medida del contenido, no un porcentaje de la pantalla.
         *
         * Antes eran el 92 % de ancho por el 90 % de alto. En un monitor de
         * 1920x1080 eso es una ventana de 1766x972 para un contenido que cabe
         * en una franja: el resultado era una pantalla de bienvenida hecha
         * casi toda de vacío, con cuatro cosas sueltas flotando. Una ventana
         * que se ajusta a lo que enseña se ve intencionada; una estirada a
         * pantalla completa se ve abandonada. */
        GdkRectangle pantalla = { 0, 0, 1280, 720 };
        GdkDisplay *disp = gdk_display_get_default();
        if (disp) {
            GdkMonitor *mon = gdk_display_get_primary_monitor(disp);
            if (!mon && gdk_display_get_n_monitors(disp) > 0)
                mon = gdk_display_get_monitor(disp, 0);
            if (mon) gdk_monitor_get_geometry(mon, &pantalla);
        }
        int an = 880, al = 580;
        /* En pantallas pequeñas manda la pantalla, no la cifra fija. */
        if (an > pantalla.width  - 80) an = pantalla.width  - 80;
        if (al > pantalla.height - 80) al = pantalla.height - 80;
        gtk_window_set_default_size(GTK_WINDOW(win), an, al);
        gtk_container_set_border_width(GTK_CONTAINER(win), 0);
    }
    gtk_window_set_resizable(GTK_WINDOW(win), TRUE);
    gtk_window_set_position(GTK_WINDOW(win), GTK_WIN_POS_CENTER);
    gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
    g_signal_connect(win, "destroy", G_CALLBACK(on_close), NULL);

    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(win), outer);

    /* ---- Cabecera ---------------------------------------------------- */
    GtkWidget *cabecera = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_name(cabecera, "cabecera");
    gtk_container_set_border_width(GTK_CONTAINER(cabecera), 28);
    gtk_box_pack_start(GTK_BOX(outer), cabecera, FALSE, FALSE, 0);

    GtkWidget *title = gtk_label_new("MIKE OS");
    gtk_widget_set_name(title, "title");
    gtk_widget_set_halign(title, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(cabecera), title, FALSE, FALSE, 0);

    GtkWidget *subtitle = gtk_label_new("Cinco atajos y ya te manejas.");
    gtk_widget_set_name(subtitle, "subtitle");
    gtk_widget_set_halign(subtitle, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(cabecera), subtitle, FALSE, FALSE, 0);

    GtkWidget *raya = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_widget_set_name(raya, "raya");
    gtk_box_pack_start(GTK_BOX(outer), raya, FALSE, FALSE, 0);

    /* ---- Dos columnas del mismo peso --------------------------------- */
    GtkWidget *cuerpo = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 24);
    gtk_container_set_border_width(GTK_CONTAINER(cuerpo), 28);
    gtk_box_pack_start(GTK_BOX(outer), cuerpo, TRUE, TRUE, 0);

    GtkWidget *izq = gtk_box_new(GTK_ORIENTATION_VERTICAL, 14);
    GtkWidget *der = gtk_box_new(GTK_ORIENTATION_VERTICAL, 14);
    gtk_box_pack_start(GTK_BOX(cuerpo), izq, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(cuerpo), der, TRUE, TRUE, 0);

    /* Izquierda: los cinco atajos, y debajo el resto plegado. */
    GtkWidget *tarjeta_atajos = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_widget_set_name(tarjeta_atajos, "tarjeta");
    gtk_container_set_border_width(GTK_CONTAINER(tarjeta_atajos), 18);
    /* Sin expandir: una tarjeta estirada a lo alto de la columna es un
     * rectángulo medio vacío con cinco líneas arriba del todo. */
    gtk_box_pack_start(GTK_BOX(izq), tarjeta_atajos, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tarjeta_atajos), build_section(&ESENCIAL), FALSE, FALSE, 0);

    GtkWidget *todos = gtk_expander_new("Ver todos los atajos");
    gtk_widget_set_name(todos, "expander");
    GtkWidget *desplaza = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(desplaza),
                                   GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_widget_set_size_request(desplaza, -1, 200);
    GtkWidget *caja_todos = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16);
    gtk_container_set_border_width(GTK_CONTAINER(caja_todos), 8);
    for (guint i = 0; i < G_N_ELEMENTS(SECTIONS); i++)
        gtk_box_pack_start(GTK_BOX(caja_todos), build_section(&SECTIONS[i]), FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(desplaza), caja_todos);
    gtk_container_add(GTK_CONTAINER(todos), desplaza);
    gtk_box_pack_start(GTK_BOX(izq), todos, FALSE, FALSE, 0);

    /* Derecha: el equipo, y un acceso al Centro de Control.
     * Donde antes había un párrafo explicando dónde estaba el panel de
     * ajustes, ahora hay un botón que lo abre. */
    /* Instalar, sólo en el USB en vivo. Hasta ahora la única forma de
     * instalar el sistema era saber que existía una orden llamada "m-install"
     * y escribirla en una terminal: quien probaba el USB no tenía ninguna
     * manera de descubrirlo. Va la primera de la columna porque es lo que la
     * mayoría quiere hacer justo después de probarlo. */
    if (en_vivo()) {
        GtkWidget *tarjeta_inst = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
        gtk_widget_set_name(tarjeta_inst, "tarjeta");
        gtk_container_set_border_width(GTK_CONTAINER(tarjeta_inst), 18);
        GtkWidget *t_in = gtk_label_new("Instalar en este equipo");
        gtk_widget_set_name(t_in, "tarjetatitulo");
        gtk_widget_set_halign(t_in, GTK_ALIGN_START);
        GtkWidget *d_in = gtk_label_new(
            "Ahora mismo MIKE OS corre en memoria: al apagar no queda nada.\n"
            "El instalador te pregunta disco, sistema de archivos y contraseña\n"
            "antes de tocar nada, y avisa de lo que va a borrar.");
        gtk_widget_set_name(d_in, "customizetext");
        gtk_widget_set_halign(d_in, GTK_ALIGN_START);
        GtkWidget *b_in = gtk_button_new_with_label("Instalar MIKE OS");
        gtk_widget_set_name(b_in, "gobtn");
        gtk_widget_set_halign(b_in, GTK_ALIGN_START);
        g_signal_connect(b_in, "clicked", G_CALLBACK(on_instalar_sistema), NULL);
        gtk_box_pack_start(GTK_BOX(tarjeta_inst), t_in, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(tarjeta_inst), d_in, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(tarjeta_inst), b_in, FALSE, FALSE, 6);
        gtk_box_pack_start(GTK_BOX(der), tarjeta_inst, FALSE, FALSE, 0);
    }

    gtk_box_pack_start(GTK_BOX(der), build_hardware(), FALSE, FALSE, 0);

    GtkWidget *tarjeta_ajustes = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_name(tarjeta_ajustes, "tarjeta");
    gtk_container_set_border_width(GTK_CONTAINER(tarjeta_ajustes), 18);
    GtkWidget *t_aj = gtk_label_new("A tu gusto");
    gtk_widget_set_name(t_aj, "tarjetatitulo");
    gtk_widget_set_halign(t_aj, GTK_ALIGN_START);
    GtkWidget *d_aj = gtk_label_new("Barra, colores, fondo, teclado y sonido.");
    gtk_widget_set_name(d_aj, "customizetext");
    gtk_widget_set_halign(d_aj, GTK_ALIGN_START);
    GtkWidget *b_aj = gtk_button_new_with_label("Abrir el Centro de Control");
    gtk_widget_set_name(b_aj, "botonsec");
    gtk_widget_set_halign(b_aj, GTK_ALIGN_START);
    g_signal_connect(b_aj, "clicked", G_CALLBACK(on_abrir_ajustes), NULL);
    gtk_box_pack_start(GTK_BOX(tarjeta_ajustes), t_aj, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tarjeta_ajustes), d_aj, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tarjeta_ajustes), b_aj, FALSE, FALSE, 6);
    gtk_box_pack_start(GTK_BOX(der), tarjeta_ajustes, FALSE, FALSE, 0);

    /* ---- Barra inferior ---------------------------------------------- */
    GtkWidget *raya2 = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_widget_set_name(raya2, "raya");
    gtk_box_pack_start(GTK_BOX(outer), raya2, FALSE, FALSE, 0);

    GtkWidget *pie = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_container_set_border_width(GTK_CONTAINER(pie), 20);
    gtk_box_pack_start(GTK_BOX(outer), pie, FALSE, FALSE, 0);

    GtkWidget *aviso = gtk_label_new("Esta ventana sólo aparece la primera vez.");
    gtk_widget_set_name(aviso, "customizetext");
    gtk_widget_set_halign(aviso, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(pie), aviso, TRUE, TRUE, 0);

    GtkWidget *btn = gtk_button_new_with_label("Empezar");
    gtk_widget_set_name(btn, "gobtn");
    g_signal_connect(btn, "clicked", G_CALLBACK(on_close), NULL);
    gtk_box_pack_end(GTK_BOX(pie), btn, FALSE, FALSE, 0);

    gtk_widget_show_all(win);
    gtk_main();
    return 0;
}
