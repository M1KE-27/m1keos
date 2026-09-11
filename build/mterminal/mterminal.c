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

    g_setenv("TERM", "xterm-256color", TRUE);
    g_setenv("COLORTERM", "truecolor", TRUE);
    vte_terminal_spawn_async(terminal, VTE_PTY_DEFAULT, cwd,
                             exec_command ? exec_argv : login_argv, NULL,
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
    GdkRGBA foreground = { 0.85, 0.85, 0.85, 1.0 };
    GdkRGBA background = { 0.07, 0.07, 0.08, terminal_alpha() };
    GdkRGBA cursor = { 0.80, 0.80, 0.82, 1.0 };
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
    g_signal_connect_swapped(app->window, "destroy", G_CALLBACK(g_free), app);
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
            exec_command = argv[i + 1];
            i++;
        } else {
            argv[forward++] = argv[i];
        }
    }
    argc = forward;
    argv[argc] = NULL;

    GtkApplication *app = gtk_application_new("org.mikeos.MTerminal", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
