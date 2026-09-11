/*
 * m-settings - Panel de ajustes nativo de MIKE Desktop.
 *
 * Lee/escribe ~/.config/mike/settings.conf (KEY=VALUE plano) y aplica los
 * cambios en caliente delegando en m-apply-settings, que regenera
 * shell.qml (desde plantilla) y el fragmento Hyprland correspondiente.
 * No hay parser de config aparte: los mismos KEY=VALUE que escribe esta
 * app son los que lee m-apply-settings con ". settings.conf" en shell.
 */
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    GtkWidget *window;
    GtkWidget *bar_position;
    GtkWidget *workspace_count;
    GtkWidget *blur_switch;
    GtkWidget *opacity_scale;
    GtkWidget *animation_speed;
    GtkWidget *accent_color;
    GtkWidget *kb_layout;
    GtkWidget *status_label;
} MSettings;

static char *config_path(const char *file) {
    const char *home = g_get_home_dir();
    return g_strdup_printf("%s/.config/mike/%s", home, file);
}

/* settings.conf es Lua real: "key = valor" (con espacios opcionales,
 * comillas para strings). m-apply-settings usa el mismo mini-parser en
 * shell -- ninguno de los dos arrastra un intérprete Lua para 7 claves. */
static char *read_setting(const char *path, const char *key, const char *fallback) {
    FILE *f = fopen(path, "r");
    if (!f) return g_strdup(fallback);
    char line[512];
    char *result = g_strdup(fallback);
    size_t keylen = strlen(key);
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (strncmp(p, key, keylen) != 0) continue;
        p += keylen;
        while (*p == ' ' || *p == '\t') p++;
        if (*p != '=') continue;
        p++;
        while (*p == ' ' || *p == '\t') p++;
        p[strcspn(p, "\n")] = 0;
        size_t len = strlen(p);
        while (len > 0 && (p[len - 1] == ' ' || p[len - 1] == '\t')) p[--len] = 0;
        if (len >= 2 && p[0] == '"' && p[len - 1] == '"') {
            p[len - 1] = 0;
            p++;
        }
        g_free(result);
        result = g_strdup(p);
        break;
    }
    fclose(f);
    return result;
}

static void load_current_settings(MSettings *app) {
    char *path = config_path("settings.conf");

    char *bar = read_setting(path, "bar_position", "top");
    gtk_combo_box_set_active_id(GTK_COMBO_BOX(app->bar_position), bar);
    g_free(bar);

    char *ws = read_setting(path, "workspace_count", "4");
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(app->workspace_count), atof(ws));
    g_free(ws);

    char *blur = read_setting(path, "blur_enabled", "false");
    gtk_switch_set_active(GTK_SWITCH(app->blur_switch), strcmp(blur, "true") == 0);
    g_free(blur);

    char *opacity = read_setting(path, "terminal_opacity", "98");
    gtk_range_set_value(GTK_RANGE(app->opacity_scale), atof(opacity));
    g_free(opacity);

    char *speed = read_setting(path, "animation_speed", "fast");
    gtk_combo_box_set_active_id(GTK_COMBO_BOX(app->animation_speed), speed);
    g_free(speed);

    char *accent = read_setting(path, "accent_color", "#00d4ff");
    GdkRGBA rgba;
    if (gdk_rgba_parse(&rgba, accent)) {
        gtk_color_chooser_set_rgba(GTK_COLOR_CHOOSER(app->accent_color), &rgba);
    }
    g_free(accent);

    char *kb = read_setting(path, "kb_layout", "us,es");
    gtk_combo_box_set_active_id(GTK_COMBO_BOX(app->kb_layout), kb);
    g_free(kb);

    g_free(path);
}

static void on_apply(GtkButton *button, gpointer user_data) {
    (void)button;
    MSettings *app = user_data;
    char *dir = config_path("");
    g_mkdir_with_parents(dir, 0700);
    g_free(dir);

    char *path = config_path("settings.conf");
    FILE *f = fopen(path, "w");
    if (!f) {
        gtk_label_set_text(GTK_LABEL(app->status_label), "Error: no se pudo escribir settings.conf");
        g_free(path);
        return;
    }

    GdkRGBA rgba;
    gtk_color_chooser_get_rgba(GTK_COLOR_CHOOSER(app->accent_color), &rgba);
    char *accent_hex = g_strdup_printf("#%02x%02x%02x",
        (int)(rgba.red * 255), (int)(rgba.green * 255), (int)(rgba.blue * 255));

    fprintf(f, "-- Generado por m-settings; Lua real (válido si alguna vez\n");
    fprintf(f, "-- se ejecuta con un intérprete), pero MIKE OS lo lee con un\n");
    fprintf(f, "-- mini-parser en shell (ver m-apply-settings).\n");
    fprintf(f, "bar_position = \"%s\"\n", gtk_combo_box_get_active_id(GTK_COMBO_BOX(app->bar_position)));
    fprintf(f, "workspace_count = %d\n", (int)gtk_spin_button_get_value(GTK_SPIN_BUTTON(app->workspace_count)));
    fprintf(f, "blur_enabled = %s\n", gtk_switch_get_active(GTK_SWITCH(app->blur_switch)) ? "true" : "false");
    fprintf(f, "terminal_opacity = %d\n", (int)gtk_range_get_value(GTK_RANGE(app->opacity_scale)));
    fprintf(f, "animation_speed = \"%s\"\n", gtk_combo_box_get_active_id(GTK_COMBO_BOX(app->animation_speed)));
    fprintf(f, "accent_color = \"%s\"\n", accent_hex);
    fprintf(f, "kb_layout = \"%s\"\n", gtk_combo_box_get_active_id(GTK_COMBO_BOX(app->kb_layout)));
    fclose(f);
    g_free(accent_hex);
    g_free(path);

    int rc = system("m-apply-settings >/tmp/.m-apply-settings.log 2>&1");
    if (rc == 0) {
        gtk_label_set_text(GTK_LABEL(app->status_label),
            "Aplicado. La opacidad de terminal se aplica a la próxima que abras.");
    } else {
        gtk_label_set_text(GTK_LABEL(app->status_label), "Aviso: m-apply-settings devolvió un error.");
    }
}

static GtkWidget *labeled_row(GtkWidget *grid, int row, const char *label, GtkWidget *control) {
    GtkWidget *l = gtk_label_new(label);
    gtk_widget_set_halign(l, GTK_ALIGN_START);
    gtk_grid_attach(GTK_GRID(grid), l, 0, row, 1, 1);
    gtk_widget_set_hexpand(control, TRUE);
    gtk_grid_attach(GTK_GRID(grid), control, 1, row, 1, 1);
    return control;
}

static void activate(GtkApplication *gtk_app, gpointer user_data) {
    (void)user_data;
    MSettings *app = g_new0(MSettings, 1);

    app->window = gtk_application_window_new(gtk_app);
    gtk_window_set_title(GTK_WINDOW(app->window), "Ajustes — MIKE OS");
    gtk_window_set_default_size(GTK_WINDOW(app->window), 480, 420);
    gtk_window_set_position(GTK_WINDOW(app->window), GTK_WIN_POS_CENTER);

    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
    gtk_widget_set_margin_start(outer, 20);
    gtk_widget_set_margin_end(outer, 20);
    gtk_widget_set_margin_top(outer, 20);
    gtk_widget_set_margin_bottom(outer, 20);
    gtk_container_add(GTK_CONTAINER(app->window), outer);

    GtkWidget *title = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(title), "<span size='large' weight='bold'>Escritorio MIKE OS</span>");
    gtk_widget_set_halign(title, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(outer), title, FALSE, FALSE, 0);

    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 14);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 16);
    gtk_box_pack_start(GTK_BOX(outer), grid, FALSE, FALSE, 4);

    int row = 0;

    app->bar_position = gtk_combo_box_text_new();
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->bar_position), "top", "Arriba");
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->bar_position), "bottom", "Abajo");
    labeled_row(grid, row++, "Posición de la barra", app->bar_position);

    app->workspace_count = gtk_spin_button_new_with_range(1, 9, 1);
    labeled_row(grid, row++, "Número de workspaces", app->workspace_count);

    app->blur_switch = gtk_switch_new();
    gtk_widget_set_halign(app->blur_switch, GTK_ALIGN_START);
    labeled_row(grid, row++, "Blur (desenfoque de fondo)", app->blur_switch);

    app->opacity_scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 10, 100, 1);
    gtk_scale_set_value_pos(GTK_SCALE(app->opacity_scale), GTK_POS_RIGHT);
    labeled_row(grid, row++, "Opacidad de la terminal (%)", app->opacity_scale);

    app->animation_speed = gtk_combo_box_text_new();
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->animation_speed), "instant", "Instantáneas (sin animación)");
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->animation_speed), "fast", "Rápidas (recomendado)");
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->animation_speed), "normal", "Normales");
    labeled_row(grid, row++, "Velocidad de animación", app->animation_speed);

    app->accent_color = gtk_color_button_new();
    gtk_widget_set_halign(app->accent_color, GTK_ALIGN_START);
    labeled_row(grid, row++, "Color de acento", app->accent_color);

    app->kb_layout = gtk_combo_box_text_new();
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->kb_layout), "us,es", "US (con ES vía Alt+Shift)");
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->kb_layout), "es,us", "ES (con US vía Alt+Shift)");
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->kb_layout), "us", "US");
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(app->kb_layout), "es", "ES");
    labeled_row(grid, row++, "Teclado", app->kb_layout);

    load_current_settings(app);

    GtkWidget *apply_btn = gtk_button_new_with_label("Aplicar");
    gtk_widget_set_halign(apply_btn, GTK_ALIGN_END);
    g_signal_connect(apply_btn, "clicked", G_CALLBACK(on_apply), app);
    gtk_box_pack_start(GTK_BOX(outer), apply_btn, FALSE, FALSE, 8);

    app->status_label = gtk_label_new("");
    gtk_widget_set_halign(app->status_label, GTK_ALIGN_START);
    gtk_label_set_line_wrap(GTK_LABEL(app->status_label), TRUE);
    gtk_box_pack_start(GTK_BOX(outer), app->status_label, FALSE, FALSE, 0);

    g_signal_connect_swapped(app->window, "destroy", G_CALLBACK(g_free), app);
    gtk_widget_show_all(app->window);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("org.mikeos.MSettings", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
