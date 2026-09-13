/*
 * MTerminal - terminal window native to MIKE OS.
 *
 * This is intentionally small: VTE supplies the battle-tested terminal
 * emulation and GTK supplies the Wayland window. The shell itself is always
 * /bin/mkshell; Kitty and other terminal front-ends are not required.
 */
#include <gtk/gtk.h>
#include <vte/vte.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct {
    GtkWidget *window;
    GtkWidget *notebook;
    /* La ventana se está cerrando.
     *
     * Hace falta porque al cerrar una ventana GTK destruye después sus hijos,
     * los intérpretes de cada pestaña mueren, y eso dispara "child-exited"
     * -- que entra en hijo_terminado() y usa esta misma estructura. Antes se
     * liberaba en cuanto la ventana emitía "destroy", así que ese manejador
     * leía memoria ya liberada y el proceso se caía.
     *
     * Y como todas las terminales viven en UN SOLO proceso, caerse ahí se
     * llevaba por delante TODAS las ventanas abiertas a la vez, con una
     * cascada de errores de GTK. Eso es el "cierro una y se cierran las cinco
     * con errores raros". */
    gboolean cerrando;
} MTerminal;

static gboolean key_press(GtkWidget *widget, GdkEventKey *event, gpointer user_data);

static const char *initial_cwd(void) {
    const char *home = g_getenv("HOME");
    return (home && *home) ? home : "/root";
}

/* Opacidad configurable desde m-settings (~/.config/mike/terminal-opacity,
 * entero 10-100). Se lee una sola vez al arrancar; cambiarla desde ajustes
 * se aplica a la siguiente terminal que se abra, no a las ya abiertas
 * (reiniciar el proceso interrumpiría la sesión de shell del usuario). */
static double terminal_alpha(void) {
    const char *home = g_getenv("HOME");
    char path[512];
    snprintf(path, sizeof(path), "%s/.config/mike/terminal-opacity", home && *home ? home : "/root");
    FILE *f = fopen(path, "r");
    if (!f) return 0.98;
    int pct = 98;
    if (fscanf(f, "%d", &pct) != 1) pct = 98;
    fclose(f);
    if (pct < 10) pct = 10;
    if (pct > 100) pct = 100;
    return pct / 100.0;
}

/* Un color de settings.json.
 *
 * Se lee a mano en vez de con una librería de JSON porque el archivo lo
 * escribe m-apply-settings con un formato fijo, una clave por línea, y meter
 * un analizador entero para sacar siete cadenas de seis caracteres sería
 * cargar la terminal con una dependencia por nada.
 *
 * Para qué: cuando la paleta sale del fondo de pantalla (m-colores), la
 * terminal tiene que ir a juego con el resto. Antes llevaba sus colores
 * escritos dentro, así que el escritorio cambiaba de color y ella se quedaba
 * en gris azulado, que es justo lo que se nota. */
static gboolean color_ajuste(const char *clave, GdkRGBA *salida) {
    const char *home = g_getenv("HOME");
    char path[512];
    snprintf(path, sizeof(path), "%s/.config/mike/settings.json",
             home && *home ? home : "/root");
    FILE *f = fopen(path, "r");
    if (!f) return FALSE;

    char linea[512];
    char patron[128];
    snprintf(patron, sizeof(patron), "\"%s\"", clave);
    gboolean hallado = FALSE;

    while (fgets(linea, sizeof(linea), f)) {
        char *k = strstr(linea, patron);
        if (!k) continue;
        /* El valor es lo que va entre las comillas de después de los dos
         * puntos: "clave": "#rrggbb", */
        char *dp = strchr(k + strlen(patron), ':');
        if (!dp) continue;
        char *c1 = strchr(dp, '"');
        if (!c1) continue;
        char *c2 = strchr(c1 + 1, '"');
        if (!c2) continue;
        *c2 = '\0';
        hallado = gdk_rgba_parse(salida, c1 + 1);
        break;
    }
    fclose(f);
    return hallado;
}

static char *tab_cwd(VteTerminal *terminal) {
    const char *uri = vte_terminal_get_current_directory_uri(terminal);
    if (!uri || !*uri) return g_strdup(initial_cwd());
    char *path = g_filename_from_uri(uri, NULL, NULL);
    return path ? path : g_strdup(initial_cwd());
}

/* Comando a ejecutar en lugar de la shell, si se pasó -e/--exec. Lo usan
 * las aplicaciones que necesitan abrir algo dentro de una terminal (por
 * ejemplo, el Centro de Control al editar la configuración a mano). NULL
 * significa el comportamiento de siempre: una sesión de login. */
static char *exec_command = NULL;

/* Los argumentos que vienen detrás de -e, cuando son varios.
 *
 * "-e" cogía UN solo argumento y le daba el resto a GTK. Con eso,
 *
 *     m-terminal -e sh -c "m-clave poner; ..."
 *
 * abría una shell pelada y le pasaba "-c" y el guion entero a GTK como
 * opciones que no entiende. O sea: el botón de poner contraseña del Centro de
 * Control no ejecutaba NADA, y desde fuera parecía que el botón no respondía.
 * Igual el de GParted del instalador. La forma de un solo argumento
 * ("-e 'vi archivo'") sí funcionaba, y por eso el fallo sobrevivió tanto: unos
 * botones iban y otros no.
 *
 * Ahora -e se lleva TODO lo que venga detrás, como hacen xterm y compañía. */
static char **exec_argv_directo = NULL;

/* La pestaña cuyo comando ya terminó se va; si era la última, la ventana
 * también. Se comprueba que el widget siga vivo porque también se llega aquí
 * al cerrar a mano con Ctrl+Shift+W, y entonces la página ya no está. */
static void hijo_terminado(VteTerminal *terminal, gint estado, gpointer datos) {
    (void)estado;
    MTerminal *app = datos;
    /* Si la ventana ya se está cerrando, no hay nada que hacer aquí y la
     * estructura puede estar a punto de desaparecer: se sale antes de tocar
     * nada. Ver el comentario de "cerrando" en la estructura. */
    if (!app || app->cerrando) return;
    if (!app->notebook || !GTK_IS_WIDGET(app->notebook)) return;
    gint pagina = gtk_notebook_page_num(GTK_NOTEBOOK(app->notebook),
                                        GTK_WIDGET(terminal));
    if (pagina < 0) return;
    gtk_notebook_remove_page(GTK_NOTEBOOK(app->notebook), pagina);
    gint quedan = gtk_notebook_get_n_pages(GTK_NOTEBOOK(app->notebook));
    gtk_notebook_set_show_tabs(GTK_NOTEBOOK(app->notebook), quedan > 1);
    if (quedan == 0 && app->window && GTK_IS_WIDGET(app->window))
        gtk_widget_destroy(app->window);
}

static void terminal_spawn(VteTerminal *terminal, const char *cwd) {
    char *login_argv[] = { (char *)"/bin/bash", (char *)"-l", NULL };
    /* Se pasa por la shell para admitir un comando completo con argumentos
     * ("vi /ruta/al/archivo") sin tener que trocearlo aquí. */
    /* Al terminar el comando se dice que ha terminado y se espera una tecla.
     *
     * Antes, la ventana se quedaba abierta sin más: pulsabas "Instalar
     * controladores", se abría una terminal, la instalación acababa en unos
     * segundos... y la ventana seguía ahí, idéntica, para siempre. Desde
     * fuera es indistinguible de una instalación colgada, y así se vivía:
     * "se queda años instalando y nunca acaba".
     *
     * Esperar una tecla en vez de cerrar sola es a propósito: si el comando
     * falló, el error tiene que poder leerse. */
    char *exec_envuelto = g_strdup_printf(
        "%s; _rc=$?; echo; "
        "if [ $_rc -eq 0 ]; then printf '\\033[32m✓ Terminado.\\033[0m'; "
        "else printf '\\033[31m✗ Terminó con error (%%s).\\033[0m' \"$_rc\"; fi; "
        "printf ' Pulsa una tecla para cerrar esta ventana.'; "
        "read -rsn1 _ </dev/tty", exec_command);
    char *exec_argv[] = { (char *)"/bin/bash", (char *)"-lc", exec_envuelto, NULL };

    /* Con varios argumentos detrás de -e se ejecutan tal cual, sin pasar por
     * una shell: así "sh -c '<guion>'" llega entero y sin que nadie le
     * reinterprete las comillas. El envoltorio de "pulsa una tecla" sólo tiene
     * sentido en la forma de un argumento, donde el texto ya es un guion. */
    char **elegido = login_argv;
    if (exec_argv_directo) elegido = exec_argv_directo;
    else if (exec_command)  elegido = exec_argv;

    g_setenv("TERM", "xterm-256color", TRUE);
    g_setenv("COLORTERM", "truecolor", TRUE);
    vte_terminal_spawn_async(terminal, VTE_PTY_DEFAULT, cwd,
                             elegido, NULL,
                             G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, -1,
                             NULL, NULL, NULL);
}

static VteTerminal *current_terminal(MTerminal *app) {
    GtkWidget *page = gtk_notebook_get_nth_page(GTK_NOTEBOOK(app->notebook),
                                                 gtk_notebook_get_current_page(GTK_NOTEBOOK(app->notebook)));
    return page && VTE_IS_TERMINAL(page) ? VTE_TERMINAL(page) : NULL;
}

static void add_tab(MTerminal *app, const char *cwd) {
    VteTerminal *terminal = VTE_TERMINAL(vte_terminal_new());
    GtkCssProvider *css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(css,
        "vte-terminal { padding: 10px; }", -1, NULL);
    gtk_style_context_add_provider(gtk_widget_get_style_context(GTK_WIDGET(terminal)),
        GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(css);

    PangoFontDescription *font = pango_font_description_from_string("Monospace 11");
    vte_terminal_set_font(terminal, font);
    pango_font_description_free(font);
    /* Los valores de aquí son los de siempre: si el archivo de ajustes falta
     * o no trae la clave, la terminal sale exactamente igual que antes. */
    GdkRGBA foreground = { 0.85, 0.85, 0.85, 1.0 };
    GdkRGBA background = { 0.07, 0.07, 0.08, 1.0 };
    GdkRGBA cursor = { 0.80, 0.80, 0.82, 1.0 };
    color_ajuste("color_texto", &foreground);
    color_ajuste("color_fondo", &background);
    if (!color_ajuste("accent_color", &cursor)) {
        cursor.red = 0.80; cursor.green = 0.80; cursor.blue = 0.82; cursor.alpha = 1.0;
    }
    /* La transparencia manda sobre lo que traiga el color: es un ajuste
     * aparte y el usuario espera que se respete. */
    background.alpha = terminal_alpha();
    cursor.alpha = 1.0;
    vte_terminal_set_colors(terminal, &foreground, &background, NULL, 0);
    vte_terminal_set_color_cursor(terminal, &cursor);
    vte_terminal_set_scrollback_lines(terminal, 10000);
    vte_terminal_set_audible_bell(terminal, FALSE);
    gtk_widget_set_hexpand(GTK_WIDGET(terminal), TRUE);
    gtk_widget_set_vexpand(GTK_WIDGET(terminal), TRUE);

    GtkWidget *label = gtk_label_new("  M  ");
    gint page = gtk_notebook_append_page(GTK_NOTEBOOK(app->notebook), GTK_WIDGET(terminal), label);
    gtk_notebook_set_tab_reorderable(GTK_NOTEBOOK(app->notebook), GTK_WIDGET(terminal), TRUE);
    g_signal_connect(terminal, "key-press-event", G_CALLBACK(key_press), app);
    /* Cuando el comando de dentro termina, se cierra la pestaña.
     *
     * Esta señal no estaba conectada, y esa es toda la historia del
     * "pulsa una tecla para cerrar esta ventana... y no se cierra": la tecla
     * SÍ se leía, el shell SÍ terminaba, pero nadie escuchaba. La pestaña se
     * quedaba con el texto muerto para siempre, que desde fuera es idéntico a
     * que la tecla no hiciera nada. */
    g_signal_connect(terminal, "child-exited", G_CALLBACK(hijo_terminado), app);
    gtk_notebook_set_show_tabs(GTK_NOTEBOOK(app->notebook),
                               gtk_notebook_get_n_pages(GTK_NOTEBOOK(app->notebook)) > 1);
    gtk_widget_show_all(GTK_WIDGET(app->notebook));
    gtk_notebook_set_current_page(GTK_NOTEBOOK(app->notebook), page);
    terminal_spawn(terminal, cwd ? cwd : initial_cwd());
    gtk_widget_grab_focus(GTK_WIDGET(terminal));
}

static gboolean key_press(GtkWidget *widget, GdkEventKey *event, gpointer user_data) {
    (void)widget;
    MTerminal *app = user_data;
    guint state = event->state & gtk_accelerator_get_default_mod_mask();
    if (state == (GDK_CONTROL_MASK | GDK_SHIFT_MASK) && event->keyval == GDK_KEY_T) {
        VteTerminal *term = current_terminal(app);
        char *cwd = term ? tab_cwd(term) : g_strdup(initial_cwd());
        add_tab(app, cwd);
        g_free(cwd);
        return TRUE;
    }
    if (state == (GDK_CONTROL_MASK | GDK_SHIFT_MASK) && event->keyval == GDK_KEY_W) {
        gint page = gtk_notebook_get_current_page(GTK_NOTEBOOK(app->notebook));
        if (page >= 0) gtk_notebook_remove_page(GTK_NOTEBOOK(app->notebook), page);
        gtk_notebook_set_show_tabs(GTK_NOTEBOOK(app->notebook),
                                   gtk_notebook_get_n_pages(GTK_NOTEBOOK(app->notebook)) > 1);
        if (gtk_notebook_get_n_pages(GTK_NOTEBOOK(app->notebook)) == 0) gtk_widget_destroy(app->window);
        return TRUE;
    }
    /* Copiar y pegar. Van con Shift a propósito: en una terminal Ctrl+C
     * interrumpe el proceso en marcha y Ctrl+V es la secuencia de escape
     * literal del shell, así que apropiárselos rompería lo que cualquiera
     * espera de una línea de órdenes. Ctrl+Shift+C/V es la convención de
     * todas las terminales de Linux, y Shift+Insert la de toda la vida.
     * Hasta ahora MTerminal no vinculaba ninguna de las dos: copiar y pegar
     * simplemente no existían. */
    if (state == (GDK_CONTROL_MASK | GDK_SHIFT_MASK) && event->keyval == GDK_KEY_C) {
        VteTerminal *term = current_terminal(app);
        if (term) vte_terminal_copy_clipboard_format(term, VTE_FORMAT_TEXT);
        return TRUE;
    }
    if (state == (GDK_CONTROL_MASK | GDK_SHIFT_MASK) && event->keyval == GDK_KEY_V) {
        VteTerminal *term = current_terminal(app);
        if (term) vte_terminal_paste_clipboard(term);
        return TRUE;
    }
    if (state == GDK_SHIFT_MASK && event->keyval == GDK_KEY_Insert) {
        VteTerminal *term = current_terminal(app);
        if (term) vte_terminal_paste_clipboard(term);
        return TRUE;
    }
    /* Seleccionar todo el búfer. Ctrl+A a secas mueve el cursor al principio
     * de la línea en bash y en cualquier shell con edición estilo readline;
     * quitárselo sería otra forma de romper la terminal. */
    if (state == (GDK_CONTROL_MASK | GDK_SHIFT_MASK) && event->keyval == GDK_KEY_A) {
        VteTerminal *term = current_terminal(app);
        if (term) vte_terminal_select_all(term);
        return TRUE;
    }

    if (state == GDK_CONTROL_MASK && (event->keyval == GDK_KEY_Page_Up || event->keyval == GDK_KEY_Page_Down)) {
        gint n = gtk_notebook_get_n_pages(GTK_NOTEBOOK(app->notebook));
        gint p = gtk_notebook_get_current_page(GTK_NOTEBOOK(app->notebook));
        if (n > 1) p = (event->keyval == GDK_KEY_Page_Up) ? (p + n - 1) % n : (p + 1) % n;
        gtk_notebook_set_current_page(GTK_NOTEBOOK(app->notebook), p);
        return TRUE;
    }
    return FALSE;
}

/* Liberar la estructura de una ventana ya cerrada, en cuanto el bucle de
 * eventos se quede sin nada urgente. */
static gboolean liberar_mas_tarde(gpointer datos) {
    g_free(datos);
    return G_SOURCE_REMOVE;
}

static void ventana_destruida(GtkWidget *w, gpointer datos) {
    (void)w;
    MTerminal *app = datos;
    if (!app) return;
    app->cerrando = TRUE;
    app->notebook = NULL;
    app->window = NULL;
    g_idle_add(liberar_mas_tarde, app);
}

static void activate(GtkApplication *gtk_app, gpointer user_data) {
    (void)user_data;
    MTerminal *app = g_new0(MTerminal, 1);
    app->window = gtk_application_window_new(gtk_app);
    app->notebook = gtk_notebook_new();
    gtk_notebook_set_show_border(GTK_NOTEBOOK(app->notebook), FALSE);
    gtk_notebook_set_scrollable(GTK_NOTEBOOK(app->notebook), TRUE);
    gtk_container_add(GTK_CONTAINER(app->window), app->notebook);
    gtk_window_set_title(GTK_WINDOW(app->window), "MTerminal — MIKE OS");
    /* Hyprland owns the surface chrome: no client-side titlebar or frame. */
    gtk_window_set_decorated(GTK_WINDOW(app->window), FALSE);
    gtk_window_set_default_size(GTK_WINDOW(app->window), 1120, 700);
    gtk_window_set_position(GTK_WINDOW(app->window), GTK_WIN_POS_CENTER);
    g_signal_connect(app->window, "key-press-event", G_CALLBACK(key_press), app);
    /* Al cerrarse la ventana se MARCA, y la estructura se libera más tarde,
     * cuando el bucle de eventos ya no tiene nada pendiente que la use.
     *
     * Antes esto era un g_free directo: la estructura desaparecía mientras GTK
     * todavía estaba destruyendo las pestañas, cuyos intérpretes al morir
     * disparan "child-exited" sobre esta misma estructura. Un proceso caído
     * ahí se lleva TODAS las ventanas de terminal, porque comparten proceso. */
    g_signal_connect(app->window, "destroy", G_CALLBACK(ventana_destruida), app);
    add_tab(app, initial_cwd());
    gtk_widget_show_all(app->window);
}

int main(int argc, char **argv) {
    /* -e / --exec <comando>: abre la terminal ejecutando ese comando en vez
     * de una shell de login. Se procesa antes que GTK y se retira de argv
     * para que la aplicación no intente interpretarlo como opción suya. */
    int forward = 1;
    for (int i = 1; i < argc; i++) {
        if ((strcmp(argv[i], "-e") == 0 || strcmp(argv[i], "--exec") == 0)
            && i + 1 < argc) {
            if (i + 2 < argc) {
                /* Varios argumentos: -e se lleva todo lo que queda, como en
                 * xterm. Antes se quedaba sólo con el primero. */
                exec_argv_directo = &argv[i + 1];
                exec_command = argv[i + 1];
            } else {
                /* Uno solo: es un guion, y va envuelto para que al terminar
                 * diga cómo fue y espere una tecla. */
                exec_command = argv[i + 1];
            }
            i = argc;
        } else {
            argv[forward++] = argv[i];
        }
    }
    argc = forward;
    argv[argc] = NULL;

    /* Con -e, cada invocación es su propio proceso.
     *
     * Con el comportamiento de instancia única de GTK, abrir una segunda
     * terminal con -e mientras ya hay una abierta sólo mandaba "activate" a la
     * primera, y el comando se perdía por el camino: el botón parecía no hacer
     * nada, pero sólo si ya tenías una terminal delante. Un fallo que aparece y
     * desaparece según lo que hubiera abierto es de los peores de diagnosticar.
     *
     * Sin -e (una terminal normal) se conserva la instancia única, que es lo
     * que hace que las nuevas salgan como pestañas de la misma ventana. */
    /* SIEMPRE su propio proceso.
     *
     * Con instancia única, cinco terminales eran cinco ventanas dentro de UN
     * solo proceso. Cualquier fallo en una se llevaba las cinco, y no hay forma
     * de hacer que un programa sea infalible: lo que hay que evitar es que un
     * fallo se propague a lo que no tiene nada que ver.
     *
     * Se pierden las pestañas compartidas entre ventanas, que nadie usaba.
     * Ctrl+Shift+T sigue abriendo pestañas dentro de su propia ventana. */
    GApplicationFlags banderas = G_APPLICATION_NON_UNIQUE;
    GtkApplication *app = gtk_application_new("org.mikeos.MTerminal", banderas);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
