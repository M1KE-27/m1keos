/*
 * m-wallpapers - navegador nativo de Wallhaven para MIKE OS.
 *
 * No reimplementa cliente HTTP ni parser JSON: delega en m-wallhaven
 * (curl + jq), que ya hace la llamada a la API pública de Wallhaven
 * (wallhaven.cc/help/api, sin key -- solo contenido SFW/general) y
 * devuelve TSV (id, url-miniatura, url-completa). Esta app solo pinta
 * la cuadrícula y llama a "m-wallhaven set <url>" al hacer clic.
 */
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    GtkWidget *window;
    GtkWidget *search_entry;
    GtkWidget *flowbox;
    GtkWidget *scroller;
    GtkWidget *status_label;
    GtkWidget *more_btn;
    char last_query[256];   /* vacío = toplist */
    int page;               /* última página cargada */
    int total;              /* resultados acumulados en la cuadrícula */

    /* Miniaturas que aún no han llegado. La cuadrícula se pinta entera al
     * instante con huecos y cada imagen se coloca en cuanto su archivo
     * termina de descargarse, en vez de tener la ventana congelada hasta
     * que están las veinticuatro. */
    GList *pendientes;      /* GtkImage* esperando su archivo */
    guint  vigilante;       /* id del temporizador que las va colocando */
    int    intentos;        /* ciclos esperando, para no vigilar sin fin */
} MWallpapers;

typedef struct {
    char id[16];
    char thumb_url[512];
    char full_url[512];
} WallItem;

static char *thumb_cache_dir(void) {
    return g_strdup_printf("%s/.cache/mike/wallhaven-thumbs", g_get_home_dir());
}

static void clear_flowbox(GtkWidget *flowbox) {
    GList *children = gtk_container_get_children(GTK_CONTAINER(flowbox));
    for (GList *l = children; l; l = l->next) {
        gtk_widget_destroy(GTK_WIDGET(l->data));
    }
    g_list_free(children);
}

static void on_set_wallpaper(GtkButton *button, gpointer user_data) {
    MWallpapers *app = user_data;
    const char *full_url = g_object_get_data(G_OBJECT(button), "full-url");
    if (!full_url) return;

    gtk_label_set_text(GTK_LABEL(app->status_label), "Descargando y aplicando...");
    while (gtk_events_pending()) gtk_main_iteration();

    char *cmd = g_strdup_printf("m-wallhaven set '%s' 2>&1", full_url);
    FILE *p = popen(cmd, "r");
    g_free(cmd);
    if (p) {
        char line[256];
        gboolean ok = FALSE;
        while (fgets(line, sizeof(line), p)) {
            if (strstr(line, "[OK]")) ok = TRUE;
        }
        pclose(p);
        gtk_label_set_text(GTK_LABEL(app->status_label),
            ok ? "Fondo aplicado." : "Error al aplicar el fondo.");
    }
}

/* Lanza la descarga de las miniaturas que falten y vuelve en el acto.
 *
 * Antes esto era un system() con curl --parallel: traía las veinticuatro a la
 * vez, sí, pero con la ventana congelada de principio a fin, así que hasta que
 * no estaban todas no se veía ninguna. Ahora cada miniatura se baja a un
 * archivo temporal y sólo se renombra al terminar, de modo que un archivo con
 * el nombre definitivo está siempre completo y se puede pintar en cuanto
 * aparece. La cuadrícula se llena sola, imagen a imagen.
 */
static void arrancar_descargas(const WallItem *items, int n) {
    char *cache_dir = thumb_cache_dir();
    g_mkdir_with_parents(cache_dir, 0700);

    GString *cmd = g_string_new("");
    int pendientes = 0;
    for (int i = 0; i < n; i++) {
        char *ruta = g_strdup_printf("%s/%s.jpg", cache_dir, items[i].id);
        if (!g_file_test(ruta, G_FILE_TEST_EXISTS)) {
            char *q_url  = g_shell_quote(items[i].thumb_url);
            char *q_ruta = g_shell_quote(ruta);
            /* El renombrado sólo ocurre si curl terminó bien: nunca queda a
             * la vista un JPEG a medias que gdk-pixbuf pintaría como basura
             * o rechazaría en silencio. */
            g_string_append_printf(cmd,
                "(curl -fsL --connect-timeout 10 --retry 1 -o %s.part %s "
                "&& mv %s.part %s) & ",
                q_ruta, q_url, q_ruta, q_ruta);
            g_free(q_url);
            g_free(q_ruta);
            pendientes++;
        }
        g_free(ruta);
    }
    g_free(cache_dir);

    if (pendientes > 0) {
        g_string_append(cmd, "wait");
        char *sh = g_strdup_printf("sh -c %s", g_shell_quote(cmd->str));
        /* Asíncrono: la ventana sigue respondiendo mientras bajan. */
        g_spawn_command_line_async(sh, NULL);
        g_free(sh);
    }
    g_string_free(cmd, TRUE);
}

/* Coloca las miniaturas que ya hayan llegado. Se llama cada pocas décimas de
 * segundo mientras quede alguna pendiente. */
static gboolean colocar_miniaturas(gpointer user_data) {
    MWallpapers *app = user_data;
    GList *siguen = NULL;

    for (GList *l = app->pendientes; l; l = l->next) {
        GtkWidget *imagen = GTK_WIDGET(l->data);
        const char *ruta = g_object_get_data(G_OBJECT(imagen), "ruta-miniatura");
        GdkPixbuf *pixbuf = ruta
            ? gdk_pixbuf_new_from_file_at_scale(ruta, 200, 130, TRUE, NULL)
            : NULL;
        if (pixbuf) {
            gtk_image_set_from_pixbuf(GTK_IMAGE(imagen), pixbuf);
            g_object_unref(pixbuf);
        } else {
            siguen = g_list_prepend(siguen, imagen);
        }
    }

    g_list_free(app->pendientes);
    app->pendientes = siguen;
    app->intentos++;

    /* Tope de espera: unos veinte segundos. Una miniatura que no llega en ese
     * tiempo no va a llegar, y seguir mirando el disco para siempre gastaría
     * batería sin dar nada a cambio. El hueco se queda vacío pero la tarjeta
     * sigue ahí y el fondo se puede aplicar igual. */
    if (!app->pendientes || app->intentos > 130) {
        if (app->pendientes) {
            g_list_free(app->pendientes);
            app->pendientes = NULL;
        }
        app->vigilante = 0;
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

static void add_result_tile(MWallpapers *app, const WallItem *item) {
    char *cache_dir = thumb_cache_dir();
    char *thumb_path = g_strdup_printf("%s/%s.jpg", cache_dir, item->id);
    g_free(cache_dir);

    /* La tarjeta se crea siempre, esté o no la miniatura. Antes se hacía
     * "if (!pixbuf) return", así que un fondo cuya miniatura fallara
     * desaparecía del catálogo sin explicación. */
    GtkWidget *image = gtk_image_new();
    gtk_widget_set_size_request(image, 200, 130);
    g_object_set_data_full(G_OBJECT(image), "ruta-miniatura",
                           g_strdup(thumb_path), g_free);

    GdkPixbuf *pixbuf = gdk_pixbuf_new_from_file_at_scale(thumb_path, 200, 130, TRUE, NULL);
    if (pixbuf) {
        /* Ya estaba en la caché: se pinta sin esperar a nada. */
        gtk_image_set_from_pixbuf(GTK_IMAGE(image), pixbuf);
        g_object_unref(pixbuf);
    } else {
        app->pendientes = g_list_prepend(app->pendientes, image);
    }
    g_free(thumb_path);

    GtkWidget *btn = gtk_button_new();
    gtk_container_add(GTK_CONTAINER(btn), image);
    gtk_widget_set_tooltip_text(btn, "Clic para poner de fondo");
    g_object_set_data_full(G_OBJECT(btn), "full-url", g_strdup(item->full_url), g_free);
    g_signal_connect(btn, "clicked", G_CALLBACK(on_set_wallpaper), app);

    gtk_flow_box_insert(GTK_FLOW_BOX(app->flowbox), btn, -1);
    gtk_widget_show_all(btn);
}

#define MAX_ITEMS 64

/* Carga una página de resultados. append=0 sustituye la cuadrícula (búsqueda
 * nueva); append=1 añade al final ("Buscar más"). */
static void load_page(MWallpapers *app, const char *query, int page, int append) {
    if (!append) {
        /* Las miniaturas pendientes apuntan a widgets de la cuadrícula que se
         * va a destruir: hay que soltarlas antes o el temporizador escribiría
         * sobre memoria ya liberada. */
        if (app->vigilante) {
            g_source_remove(app->vigilante);
            app->vigilante = 0;
        }
        g_list_free(app->pendientes);
        app->pendientes = NULL;
        clear_flowbox(app->flowbox);
        app->total = 0;
    }
    gtk_widget_set_sensitive(app->more_btn, FALSE);
    gtk_label_set_text(GTK_LABEL(app->status_label),
                       append ? "Cargando más..." : "Buscando...");
    while (gtk_events_pending()) gtk_main_iteration();

    char *cmd;
    if (query && *query) {
        char *escaped = g_shell_quote(query);
        cmd = g_strdup_printf("m-wallhaven search %s %d 2>/dev/null", escaped, page);
        g_free(escaped);
    } else {
        cmd = g_strdup_printf("m-wallhaven toplist %d 2>/dev/null", page);
    }

    FILE *p = popen(cmd, "r");
    g_free(cmd);
    if (!p) {
        gtk_label_set_text(GTK_LABEL(app->status_label), "Error al consultar Wallhaven.");
        gtk_widget_set_sensitive(app->more_btn, TRUE);
        return;
    }

    /* Se leen todos los resultados antes de pintar nada: así las miniaturas se
     * pueden pedir de golpe en paralelo en vez de una por una. */
    WallItem items[MAX_ITEMS];
    int count = 0;
    char line[1024];
    while (count < MAX_ITEMS && fgets(line, sizeof(line), p)) {
        char *tab1 = strchr(line, '\t');
        if (!tab1) continue;
        *tab1 = 0;
        char *tab2 = strchr(tab1 + 1, '\t');
        if (!tab2) continue;
        *tab2 = 0;
        char *end = tab2 + 1;
        end[strcspn(end, "\n")] = 0;

        memset(&items[count], 0, sizeof(WallItem));
        g_strlcpy(items[count].id, line, sizeof(items[count].id));
        g_strlcpy(items[count].thumb_url, tab1 + 1, sizeof(items[count].thumb_url));
        g_strlcpy(items[count].full_url, end, sizeof(items[count].full_url));
        count++;
    }
    pclose(p);

    if (count > 0) {
        /* Primero se lanzan las descargas y acto seguido se pinta la
         * cuadrícula entera. La ventana queda utilizable desde el primer
         * momento y las miniaturas van cayendo dentro. */
        arrancar_descargas(items, count);
        for (int i = 0; i < count; i++) add_result_tile(app, &items[i]);
        app->total += count;
        app->page = page;

        if (app->pendientes && app->vigilante == 0) {
            app->intentos = 0;
            app->vigilante = g_timeout_add(150, colocar_miniaturas, app);
        }
    }

    char *status;
    if (app->total > 0) {
        status = g_strdup_printf("%d resultados.", app->total);
    } else {
        status = g_strdup("Sin resultados.");
    }
    gtk_label_set_text(GTK_LABEL(app->status_label), status);
    g_free(status);

    /* Si la página vino vacía, no hay más que traer. */
    gtk_widget_set_sensitive(app->more_btn, count > 0);
}

static void run_search(MWallpapers *app, const char *query) {
    g_strlcpy(app->last_query, query ? query : "", sizeof(app->last_query));
    load_page(app, app->last_query, 1, 0);
}

static void on_search_activate(GtkEntry *entry, gpointer user_data) {
    MWallpapers *app = user_data;
    run_search(app, gtk_entry_get_text(entry));
}

static void on_search_clicked(GtkButton *button, gpointer user_data) {
    (void)button;
    MWallpapers *app = user_data;
    run_search(app, gtk_entry_get_text(GTK_ENTRY(app->search_entry)));
}

static void on_more_clicked(GtkButton *button, gpointer user_data) {
    (void)button;
    MWallpapers *app = user_data;
    load_page(app, app->last_query, app->page + 1, 1);
}

static void activate(GtkApplication *gtk_app, gpointer user_data) {
    (void)user_data;
    MWallpapers *app = g_new0(MWallpapers, 1);

    app->window = gtk_application_window_new(gtk_app);
    gtk_window_set_title(GTK_WINDOW(app->window), "Fondos de pantalla — Wallhaven");
    gtk_window_set_default_size(GTK_WINDOW(app->window), 900, 640);
    gtk_window_set_position(GTK_WINDOW(app->window), GTK_WIN_POS_CENTER);

    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_widget_set_margin_start(outer, 16);
    gtk_widget_set_margin_end(outer, 16);
    gtk_widget_set_margin_top(outer, 16);
    gtk_widget_set_margin_bottom(outer, 16);
    gtk_container_add(GTK_CONTAINER(app->window), outer);

    GtkWidget *search_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    app->search_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(app->search_entry), "Buscar en Wallhaven (ej: mountains, space, minimal)...");
    gtk_widget_set_hexpand(app->search_entry, TRUE);
    g_signal_connect(app->search_entry, "activate", G_CALLBACK(on_search_activate), app);
    GtkWidget *search_btn = gtk_button_new_with_label("Buscar");
    g_signal_connect(search_btn, "clicked", G_CALLBACK(on_search_clicked), app);
    gtk_box_pack_start(GTK_BOX(search_row), app->search_entry, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(search_row), search_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(outer), search_row, FALSE, FALSE, 0);

    app->scroller = gtk_scrolled_window_new(NULL, NULL);
    gtk_widget_set_vexpand(app->scroller, TRUE);
    app->flowbox = gtk_flow_box_new();
    gtk_flow_box_set_selection_mode(GTK_FLOW_BOX(app->flowbox), GTK_SELECTION_NONE);
    gtk_flow_box_set_homogeneous(GTK_FLOW_BOX(app->flowbox), TRUE);
    gtk_container_add(GTK_CONTAINER(app->scroller), app->flowbox);
    gtk_box_pack_start(GTK_BOX(outer), app->scroller, TRUE, TRUE, 0);

    GtkWidget *bottom_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    app->status_label = gtk_label_new("Cargando destacados...");
    gtk_widget_set_halign(app->status_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(bottom_row), app->status_label, TRUE, TRUE, 0);

    app->more_btn = gtk_button_new_with_label("Buscar más");
    gtk_widget_set_tooltip_text(app->more_btn, "Cargar la siguiente página de resultados");
    g_signal_connect(app->more_btn, "clicked", G_CALLBACK(on_more_clicked), app);
    gtk_box_pack_start(GTK_BOX(bottom_row), app->more_btn, FALSE, FALSE, 0);

    gtk_box_pack_start(GTK_BOX(outer), bottom_row, FALSE, FALSE, 0);

    g_signal_connect_swapped(app->window, "destroy", G_CALLBACK(g_free), app);
    gtk_widget_show_all(app->window);

    run_search(app, NULL);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("org.mikeos.MWallpapers", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
