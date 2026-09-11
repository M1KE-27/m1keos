/*
 * MKShell - MIKE OS Native Shell (v0.2.0 Core)
 * Ultralight, Fast, POSIX-compatible interactive and scripting shell.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <termios.h>
#include <dirent.h>
#include <ctype.h>

#define MKSHELL_VERSION "0.2.0"
#define MAX_LINE_LEN 2048
#define MAX_ARGS 128
#define MAX_PIPES 16
#define MAX_HISTORY 100
#define MAX_ALIASES 32

static int last_exit_code = 0;
static char history[MAX_HISTORY][MAX_LINE_LEN];
static int history_count = 0;

typedef struct {
    char name[64];
    char value[256];
} Alias;

static Alias aliases[MAX_ALIASES];
static int alias_count = 0;

#define MAX_BG_JOBS 64
static pid_t bg_pids[MAX_BG_JOBS];
static int bg_count = 0;

/* Reapea (sin bloquear) los jobs en segundo plano ya terminados, evitando
 * que se acumulen zombis. Solo espera PIDs que sabemos son de background,
 * nunca -1, para no robarle el estado de salida a un wait() en primer plano. */
void reap_background_jobs(void) {
    for (int i = 0; i < bg_count; ) {
        int status;
        pid_t r = waitpid(bg_pids[i], &status, WNOHANG);
        if (r > 0) {
            printf("[bg] PID %d terminado\n", r);
            bg_pids[i] = bg_pids[--bg_count];
        } else {
            i++;
        }
    }
}

/* Colors for interactive prompt */
#define COLOR_RESET   "\033[0m"
#define COLOR_CYAN    "\033[1;36m"
#define COLOR_GREEN   "\033[1;32m"
#define COLOR_BLUE    "\033[1;34m"
#define COLOR_RED     "\033[1;31m"
#define COLOR_YELLOW  "\033[1;33m"
#define COLOR_MAGENTA "\033[1;35m"

void sigint_handler(int sig) {
    (void)sig;
    printf("\n");
    fflush(stdout);
}

void add_history(const char *cmd) {
    if (!cmd || strlen(cmd) == 0) return;
    if (history_count > 0 && strcmp(history[(history_count - 1) % MAX_HISTORY], cmd) == 0) return;
    strncpy(history[history_count % MAX_HISTORY], cmd, MAX_LINE_LEN - 1);
    history_count++;
}

void print_prompt(void) {
    char cwd[1024];
    char hostname[256];
    const char *user = getenv("USER");
    if (!user) user = (geteuid() == 0) ? "root" : "mike";
    if (gethostname(hostname, sizeof(hostname)) != 0) strcpy(hostname, "mikeos");
    if (!getcwd(cwd, sizeof(cwd))) strcpy(cwd, "?");

    const char *home = getenv("HOME");
    char display_cwd[1024];
    if (home && strncmp(cwd, home, strlen(home)) == 0) {
        snprintf(display_cwd, sizeof(display_cwd), "~%s", cwd + strlen(home));
    } else {
        snprintf(display_cwd, sizeof(display_cwd), "%s", cwd);
    }

    int is_root = (geteuid() == 0);
    const char *prompt_char = is_root ? "#" : "$";

    /* Keep the prompt stable and uncluttered after failed commands. The exit
       status remains available through `$?`, but no numeric code pollutes the
       next command line. */
    printf(COLOR_CYAN "M" COLOR_MAGENTA "OS" COLOR_RESET " " COLOR_GREEN "[%s@%s" COLOR_RESET " " COLOR_BLUE "%s" COLOR_GREEN "]" COLOR_RESET "%s ",
           user, hostname, display_cwd, prompt_char);
    fflush(stdout);
}

/* -------------------------------------------------------------------------
 * Small readline-style editor. It keeps MKShell dependency-free while still
 * providing the things expected from a modern terminal: arrows, history,
 * cursor movement and context-aware Tab completion for commands and paths.
 * ------------------------------------------------------------------------- */
static void redraw_input(const char *line, size_t length, size_t cursor) {
    printf("\r\033[2K");
    print_prompt();
    if (length) fwrite(line, 1, length, stdout);
    if (cursor < length) printf("\033[%zuD", length - cursor);
    fflush(stdout);
}

static int completion_exists(char **items, int count, const char *item) {
    for (int i = 0; i < count; i++) if (strcmp(items[i], item) == 0) return 1;
    return 0;
}

static int collect_completions(const char *prefix, char **items, int max_items) {
    int count = 0;
    int command_position = 1;
    for (const char *p = prefix; *p; p++) {
        if (isspace((unsigned char)*p)) { command_position = 0; break; }
    }

    char directory[1024] = ".";
    char base[512];
    const char *slash = strrchr(prefix, '/');
    if (slash) {
        size_t n = (size_t)(slash - prefix);
        if (n == 0) strcpy(directory, "/");
        else if (n < sizeof(directory)) { memcpy(directory, prefix, n); directory[n] = '\0'; }
        snprintf(base, sizeof(base), "%s", slash + 1);
    } else {
        strncpy(base, prefix, sizeof(base) - 1);
        base[sizeof(base) - 1] = '\0';
        if (command_position) strcpy(directory, ".");
    }

    if (command_position && !slash) {
        const char *path = getenv("PATH");
        if (path) {
            char *copy = strdup(path);
            for (char *dir = strtok(copy, ":"); dir && count < max_items; dir = strtok(NULL, ":")) {
                DIR *dp = opendir(*dir ? dir : ".");
                if (!dp) continue;
                struct dirent *entry;
                while ((entry = readdir(dp)) && count < max_items) {
                    if (strncmp(entry->d_name, base, strlen(base)) != 0) continue;
                    char candidate[512];
                    snprintf(candidate, sizeof(candidate), "%s", entry->d_name);
                    char full[1536];
                    snprintf(full, sizeof(full), "%s/%s", *dir ? dir : ".", entry->d_name);
                    if (access(full, X_OK) == 0 && !completion_exists(items, count, candidate))
                        items[count++] = strdup(candidate);
                }
                closedir(dp);
            }
            free(copy);
        }
    } else {
        DIR *dp = opendir(directory);
        if (dp) {
            struct dirent *entry;
            while ((entry = readdir(dp)) && count < max_items) {
                if (strncmp(entry->d_name, base, strlen(base)) != 0) continue;
                items[count++] = strdup(entry->d_name);
            }
            closedir(dp);
        }
    }
    return count;
}

static void free_completions(char **items, int count) {
    for (int i = 0; i < count; i++) free(items[i]);
}

static int complete_line(char *line, size_t *length, size_t *cursor) {
    size_t start = *cursor;
    while (start > 0 && !isspace((unsigned char)line[start - 1])) start--;
    char prefix[1024];
    size_t prefix_len = *cursor - start;
    if (prefix_len >= sizeof(prefix)) return 0;
    memcpy(prefix, line + start, prefix_len);
    prefix[prefix_len] = '\0';
    char *matches[128] = {0};
    int count = collect_completions(prefix, matches, 128);
    if (count == 0) return 0;
    if (count == 1) {
        const char *value = matches[0];
        size_t value_len = strlen(value);
        size_t tail = *length - *cursor;
        if (*length - prefix_len + value_len + 1 >= MAX_LINE_LEN) { free_completions(matches, count); return 0; }
        memmove(line + start + value_len, line + *cursor, tail + 1);
        memcpy(line + start, value, value_len);
        *cursor = start + value_len;
        *length = *length - prefix_len + value_len;
        if (*cursor == *length && (start == 0 || line[start - 1] != '/')) line[(*length)++] = ' ', line[*length] = '\0', (*cursor)++;
    } else {
        printf("\n");
        for (int i = 0; i < count; i++) printf("%s%s", matches[i], (i % 5 == 4 || i == count - 1) ? "\n" : "  ");
    }
    free_completions(matches, count);
    return 1;
}

static int read_interactive_line(char *line, size_t capacity) {
    struct termios original, raw;
    if (tcgetattr(STDIN_FILENO, &original) != 0) return fgets(line, capacity, stdin) ? 0 : -1;
    raw = original;
    raw.c_lflag &= (tcflag_t)~(ECHO | ICANON | IEXTEN);
    raw.c_iflag &= (tcflag_t)~(IXON | ICRNL);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);

    size_t length = 0, cursor = 0;
    int history_index = history_count;
    line[0] = '\0';
    while (1) {
        unsigned char ch;
        ssize_t got = read(STDIN_FILENO, &ch, 1);
        if (got <= 0) { tcsetattr(STDIN_FILENO, TCSAFLUSH, &original); return -1; }
        if (ch == '\r' || ch == '\n') { line[length] = '\0'; putchar('\n'); break; }
        if (ch == 4) { /* Ctrl-D */ if (length == 0) { putchar('\n'); tcsetattr(STDIN_FILENO, TCSAFLUSH, &original); return -1; } continue; }
        if (ch == 3) { line[0] = '\0'; length = cursor = 0; putchar('^'); putchar('C'); putchar('\n'); break; }
        if (ch == '\t') { if (complete_line(line, &length, &cursor)) redraw_input(line, length, cursor); else putchar('\a'); continue; }
        if (ch == 127 || ch == 8) {
            if (cursor > 0) { memmove(line + cursor - 1, line + cursor, length - cursor + 1); cursor--; length--; redraw_input(line, length, cursor); }
            else putchar('\a');
            continue;
        }
        if (ch == 27) {
            unsigned char seq[2];
            if (read(STDIN_FILENO, seq, 2) != 2 || seq[0] != '[') continue;
            if (seq[1] == 'D' && cursor > 0) cursor--;
            else if (seq[1] == 'C' && cursor < length) cursor++;
            else if (seq[1] == 'A' || seq[1] == 'B') {
                if (history_count == 0) continue;
                if (seq[1] == 'A' && history_index > 0) history_index--;
                if (seq[1] == 'B' && history_index < history_count) history_index++;
                if (history_index < history_count) snprintf(line, capacity, "%s", history[history_index % MAX_HISTORY]);
                else line[0] = '\0';
                length = cursor = strlen(line);
            }
            redraw_input(line, length, cursor);
            continue;
        }
        if (ch >= 32 && ch != 127 && length + 1 < capacity) {
            memmove(line + cursor + 1, line + cursor, length - cursor + 1);
            line[cursor++] = (char)ch;
            length++;
            redraw_input(line, length, cursor);
        }
    }
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &original);
    return 0;
}

/* Expand variables like $VAR, $?, $USER, $HOME, etc. */
/* Copia hasta 'n' bytes de src a *out_ptr, sin exceder 'end', y avanza
 * *out_ptr. Devuelve 0 si cupo entero, -1 si se truncó (buffer lleno). */
static int bounded_append(char **out_ptr, const char *end, const char *src) {
    size_t avail = (size_t)(end - *out_ptr);
    size_t len = strlen(src);
    if (len >= avail) {
        memcpy(*out_ptr, src, avail > 0 ? avail - 1 : 0);
        *out_ptr += (avail > 0 ? avail - 1 : 0);
        return -1;
    }
    memcpy(*out_ptr, src, len);
    *out_ptr += len;
    return 0;
}

char *expand_variables(const char *input) {
    static char output[MAX_LINE_LEN * 2];
    char *out_ptr = output;
    const char *in_ptr = input;
    /* Reservar 1 byte final para el terminador NUL. */
    char *end = output + sizeof(output) - 1;

    while (*in_ptr && out_ptr < end) {
        if (*in_ptr == '$') {
            in_ptr++;
            if (*in_ptr == '?') {
                char num[16];
                snprintf(num, sizeof(num), "%d", last_exit_code);
                if (bounded_append(&out_ptr, end, num) != 0) break;
                in_ptr++;
            } else if (*in_ptr == '$') {
                char num[16];
                snprintf(num, sizeof(num), "%d", getpid());
                if (bounded_append(&out_ptr, end, num) != 0) break;
                in_ptr++;
            } else {
                char var_name[128];
                int i = 0;
                while ((*in_ptr >= 'A' && *in_ptr <= 'Z') ||
                       (*in_ptr >= 'a' && *in_ptr <= 'z') ||
                       (*in_ptr >= '0' && *in_ptr <= '9') ||
                       *in_ptr == '_') {
                    if (i < 127) var_name[i++] = *in_ptr;
                    in_ptr++;
                }
                var_name[i] = '\0';
                if (i > 0) {
                    char *val = getenv(var_name);
                    if (val) {
                        if (bounded_append(&out_ptr, end, val) != 0) break;
                    }
                } else if (out_ptr < end) {
                    *out_ptr++ = '$';
                }
            }
        } else if (*in_ptr == '~' && (in_ptr == input || *(in_ptr - 1) == ' ')) {
            const char *home = getenv("HOME");
            if (home) {
                if (bounded_append(&out_ptr, end, home) != 0) break;
            } else if (out_ptr < end) {
                *out_ptr++ = '~';
            }
            in_ptr++;
        } else {
            *out_ptr++ = *in_ptr++;
        }
    }
    *out_ptr = '\0';
    return output;
}

int is_builtin(const char *cmd) {
    if (!cmd) return 0;
    return (strcmp(cmd, "cd") == 0 ||
            strcmp(cmd, "exit") == 0 ||
            strcmp(cmd, "help") == 0 ||
            strcmp(cmd, "export") == 0 ||
            strcmp(cmd, "unset") == 0 ||
            strcmp(cmd, "alias") == 0 ||
            strcmp(cmd, "history") == 0 ||
            strcmp(cmd, "pwd") == 0 ||
            strcmp(cmd, "version") == 0 ||
            strcmp(cmd, "source") == 0 ||
            strcmp(cmd, ".") == 0);
}

int run_script(const char *filename);

int execute_builtin(char **args, int in_fd, int out_fd) {
    (void)in_fd;
    (void)out_fd;
    if (!args[0]) return 0;

    if (strcmp(args[0], "exit") == 0) {
        int code = (args[1]) ? atoi(args[1]) : last_exit_code;
        exit(code);
    }
    if (strcmp(args[0], "cd") == 0) {
        const char *dir = args[1];
        if (!dir || strcmp(dir, "~") == 0) {
            dir = getenv("HOME");
            if (!dir) dir = "/root";
        }
        if (chdir(dir) != 0) {
            perror("cd");
            last_exit_code = 1;
        } else {
            char cwd[1024];
            if (getcwd(cwd, sizeof(cwd))) setenv("PWD", cwd, 1);
            last_exit_code = 0;
        }
        return last_exit_code;
    }
    if (strcmp(args[0], "pwd") == 0) {
        char cwd[1024];
        if (getcwd(cwd, sizeof(cwd))) {
            printf("%s\n", cwd);
            last_exit_code = 0;
        } else {
            perror("pwd");
            last_exit_code = 1;
        }
        return last_exit_code;
    }
    if (strcmp(args[0], "export") == 0) {
        if (!args[1]) {
            extern char **environ;
            for (char **e = environ; *e; e++) puts(*e);
            last_exit_code = 0;
            return 0;
        }
        char *eq = strchr(args[1], '=');
        if (eq) {
            *eq = '\0';
            setenv(args[1], eq + 1, 1);
        } else if (args[2]) {
            setenv(args[1], args[2], 1);
        }
        last_exit_code = 0;
        return 0;
    }
    if (strcmp(args[0], "unset") == 0) {
        if (args[1]) unsetenv(args[1]);
        last_exit_code = 0;
        return 0;
    }
    if (strcmp(args[0], "alias") == 0) {
        if (!args[1]) {
            for (int i = 0; i < alias_count; i++) {
                printf("alias %s='%s'\n", aliases[i].name, aliases[i].value);
            }
            last_exit_code = 0;
            return 0;
        }
        char *eq = strchr(args[1], '=');
        if (eq && alias_count < MAX_ALIASES) {
            *eq = '\0';
            char *val = eq + 1;
            if (*val == '\'' || *val == '"') val++;
            int len = strlen(val);
            if (len > 0 && (val[len - 1] == '\'' || val[len - 1] == '"')) val[len - 1] = '\0';
            strncpy(aliases[alias_count].name, args[1], 63);
            strncpy(aliases[alias_count].value, val, 255);
            alias_count++;
        }
        last_exit_code = 0;
        return 0;
    }
    if (strcmp(args[0], "history") == 0) {
        int start = (history_count > MAX_HISTORY) ? history_count - MAX_HISTORY : 0;
        for (int i = start; i < history_count; i++) {
            printf("%4d  %s\n", i + 1, history[i % MAX_HISTORY]);
        }
        last_exit_code = 0;
        return 0;
    }
    if (strcmp(args[0], "version") == 0) {
        printf("MKShell v%s (MIKE OS Native Shell)\n", MKSHELL_VERSION);
        printf("Built for extreme speed and clean Unix compatibility.\n");
        last_exit_code = 0;
        return 0;
    }
    if (strcmp(args[0], "help") == 0) {
        printf("MKShell - MIKE OS Native Shell v%s\n", MKSHELL_VERSION);
        printf("Built-in commands:\n");
        printf("  cd [dir]        Change current directory\n");
        printf("  pwd             Print current working directory\n");
        printf("  export VAR=VAL  Set environment variable\n");
        printf("  unset VAR       Remove environment variable\n");
        printf("  alias name=cmd  Define command alias\n");
        printf("  history         List command history\n");
        printf("  source <file>   Execute commands from file\n");
        printf("  version         Display MKShell version\n");
        printf("  exit [code]     Exit MKShell\n");
        printf("  help            Show this help message\n");
        last_exit_code = 0;
        return 0;
    }
    if (strcmp(args[0], "source") == 0 || strcmp(args[0], ".") == 0) {
        if (!args[1]) {
            fprintf(stderr, "source: filename argument required\n");
            last_exit_code = 1;
            return 1;
        }
        return run_script(args[1]);
    }
    return 0;
}

/* Tokenizador consciente de comillas: extrae el siguiente token de *p,
 * respetando ' ' y " " (sin expansión dentro de comillas simples), y deja
 * *p apuntando tras el token. Escribe el token (sin comillas) in-place y
 * devuelve un puntero a él, o NULL si no queda nada. */
static char *next_token(char **p) {
    char *s = *p;
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') s++;
    if (*s == '\0') { *p = s; return NULL; }

    char *out = s;
    char *write = s;
    char quote = 0;
    while (*out) {
        if (quote) {
            if (*out == quote) { quote = 0; out++; continue; }
            *write++ = *out++;
        } else if (*out == '\'' || *out == '"') {
            quote = *out++;
        } else if (*out == ' ' || *out == '\t' || *out == '\r' || *out == '\n') {
            break;
        } else {
            *write++ = *out++;
        }
    }
    if (*out) out++; /* consumir el separador */
    *write = '\0';
    *p = out;
    return s;
}

int parse_command_args(char *cmd_str, char **args, char **in_file, char **out_file, int *append_out, int *is_bg, int *merge_stderr) {
    int count = 0;
    *in_file = NULL;
    *out_file = NULL;
    *append_out = 0;
    *is_bg = 0;
    *merge_stderr = 0;

    char *cursor = cmd_str;
    char *token = next_token(&cursor);
    while (token != NULL && count < MAX_ARGS - 1) {
        if (strcmp(token, "<") == 0) {
            token = next_token(&cursor);
            if (token) *in_file = token;
        } else if (strncmp(token, "<", 1) == 0 && strlen(token) > 1) {
            *in_file = token + 1;
        } else if (strcmp(token, ">>") == 0) {
            token = next_token(&cursor);
            if (token) { *out_file = token; *append_out = 1; }
        } else if (strncmp(token, ">>", 2) == 0 && strlen(token) > 2) {
            *out_file = token + 2; *append_out = 1;
        } else if (strcmp(token, ">") == 0) {
            token = next_token(&cursor);
            if (token) { *out_file = token; *append_out = 0; }
        } else if (strncmp(token, ">", 1) == 0 && strlen(token) > 1) {
            *out_file = token + 1; *append_out = 0;
        } else if (strcmp(token, "2>&1") == 0) {
            *merge_stderr = 1;
        } else if (strcmp(token, "&") == 0) {
            *is_bg = 1;
        } else {
            args[count++] = token;
        }
        token = next_token(&cursor);
    }
    args[count] = NULL;
    return count;
}

int parse_and_execute_single(char *cmd_str, int in_fd, int out_fd, int is_bg) {
    char *args[MAX_ARGS];
    char *input_file = NULL;
    char *output_file = NULL;
    int append_out = 0;
    int merge_stderr = 0;

    int arg_count = parse_command_args(cmd_str, args, &input_file, &output_file, &append_out, &is_bg, &merge_stderr);
    if (arg_count == 0) return 0;

    /* Check aliases: el valor puede tener varias palabras (ej. "ls -la"),
     * hay que insertarlas como argv separados, no como un solo args[0]. */
    for (int i = 0; i < alias_count; i++) {
        if (strcmp(args[0], aliases[i].name) == 0) {
            static char alias_buf[256];
            strncpy(alias_buf, aliases[i].value, sizeof(alias_buf) - 1);
            alias_buf[sizeof(alias_buf) - 1] = '\0';

            char *alias_args[MAX_ARGS];
            int alias_n = 0;
            char *ac = alias_buf;
            char *at = next_token(&ac);
            while (at && alias_n < MAX_ARGS - 1) {
                alias_args[alias_n++] = at;
                at = next_token(&ac);
            }
            if (alias_n > 0) {
                int shift = alias_n - 1;
                int room = MAX_ARGS - 1 - arg_count;
                if (shift > room) shift = room;
                if (shift > 0) {
                    for (int k = arg_count; k >= 1; k--) {
                        if (k + shift <= MAX_ARGS - 1) args[k + shift] = args[k];
                    }
                }
                for (int k = 0; k < alias_n && k <= shift; k++) args[k] = alias_args[k];
                arg_count += shift;
                args[arg_count] = NULL;
            }
            break;
        }
    }

    if (is_builtin(args[0])) {
        return execute_builtin(args, in_fd, out_fd);
    }

    /* Redirections */
    if (input_file) {
        int fd = open(input_file, O_RDONLY);
        if (fd < 0) {
            perror(input_file);
            last_exit_code = 1;
            return 1;
        }
        in_fd = fd;
    }
    if (output_file) {
        int flags = O_WRONLY | O_CREAT | (append_out ? O_APPEND : O_TRUNC);
        int fd = open(output_file, flags, 0644);
        if (fd < 0) {
            perror(output_file);
            last_exit_code = 1;
            return 1;
        }
        out_fd = fd;
    }

    pid_t pid = fork();
    if (pid == 0) {
        if (in_fd != STDIN_FILENO) {
            dup2(in_fd, STDIN_FILENO);
            close(in_fd);
        }
        if (out_fd != STDOUT_FILENO) {
            dup2(out_fd, STDOUT_FILENO);
            close(out_fd);
        }
        if (merge_stderr) dup2(STDOUT_FILENO, STDERR_FILENO);
        execvp(args[0], args);
        fprintf(stderr, "mkshell: %s: command not found\n", args[0]);
        exit(127);
    } else if (pid > 0) {
        if (in_fd != STDIN_FILENO) close(in_fd);
        if (out_fd != STDOUT_FILENO) close(out_fd);

        if (!is_bg) {
            int status;
            waitpid(pid, &status, 0);
            if (WIFEXITED(status)) {
                last_exit_code = WEXITSTATUS(status);
            } else if (WIFSIGNALED(status)) {
                last_exit_code = 128 + WTERMSIG(status);
            }
        } else {
            printf("[bg] PID %d\n", pid);
            if (bg_count < MAX_BG_JOBS) bg_pids[bg_count++] = pid;
            last_exit_code = 0;
        }
    } else {
        perror("fork");
        last_exit_code = 1;
    }
    return last_exit_code;
}

int execute_pipeline(char *line) {
    char *commands[MAX_PIPES];
    int num_cmds = 0;

    char *cmd = strtok(line, "|");
    while (cmd != NULL && num_cmds < MAX_PIPES) {
        commands[num_cmds++] = cmd;
        cmd = strtok(NULL, "|");
    }

    if (num_cmds == 0) return 0;
    if (num_cmds == 1) {
        return parse_and_execute_single(commands[0], STDIN_FILENO, STDOUT_FILENO, 0);
    }

    int pipefds[2 * (num_cmds - 1)];
    for (int i = 0; i < num_cmds - 1; i++) {
        if (pipe(pipefds + i * 2) < 0) {
            perror("pipe");
            return 1;
        }
    }

    pid_t child_pids[MAX_PIPES];
    int forked_count = 0;
    pid_t last_pid = -1;

    for (int i = 0; i < num_cmds; i++) {
        int in_fd = (i == 0) ? STDIN_FILENO : pipefds[(i - 1) * 2];
        int out_fd = (i == num_cmds - 1) ? STDOUT_FILENO : pipefds[i * 2 + 1];

        char *args[MAX_ARGS];
        char *input_file = NULL;
        char *output_file = NULL;
        int append_out = 0;
        int is_bg = 0;
        int merge_stderr = 0;

        int arg_count = parse_command_args(commands[i], args, &input_file, &output_file, &append_out, &is_bg, &merge_stderr);
        if (arg_count == 0) continue;

        pid_t pid = fork();
        if (pid < 0) {
            perror("fork");
            continue;
        }
        if (pid == 0) {
            if (input_file) {
                int fd = open(input_file, O_RDONLY);
                if (fd < 0) { perror(input_file); exit(1); }
                dup2(fd, STDIN_FILENO); close(fd);
            } else if (in_fd != STDIN_FILENO) {
                dup2(in_fd, STDIN_FILENO);
            }

            if (output_file) {
                int flags = O_WRONLY | O_CREAT | (append_out ? O_APPEND : O_TRUNC);
                int fd = open(output_file, flags, 0644);
                if (fd < 0) { perror(output_file); exit(1); }
                dup2(fd, STDOUT_FILENO); close(fd);
            } else if (out_fd != STDOUT_FILENO) {
                dup2(out_fd, STDOUT_FILENO);
            }
            if (merge_stderr) dup2(STDOUT_FILENO, STDERR_FILENO);

            for (int j = 0; j < 2 * (num_cmds - 1); j++) {
                close(pipefds[j]);
            }

            if (is_builtin(args[0])) {
                exit(execute_builtin(args, in_fd, out_fd));
            }
            execvp(args[0], args);
            fprintf(stderr, "mkshell: %s: command not found\n", args[0]);
            exit(127);
        }
        child_pids[forked_count++] = pid;
        if (i == num_cmds - 1) last_pid = pid;
    }

    for (int i = 0; i < 2 * (num_cmds - 1); i++) {
        close(pipefds[i]);
    }

    for (int i = 0; i < forked_count; i++) {
        int status;
        pid_t got = waitpid(child_pids[i], &status, 0);
        if (got == last_pid && WIFEXITED(status)) {
            last_exit_code = WEXITSTATUS(status);
        } else if (got == last_pid && WIFSIGNALED(status)) {
            last_exit_code = 128 + WTERMSIG(status);
        }
    }
    return last_exit_code;
}

int process_line(char *line) {
    while (*line == ' ' || *line == '\t') line++;
    if (*line == '\0' || *line == '#') return 0;

    char copy[MAX_LINE_LEN];
    strncpy(copy, line, sizeof(copy) - 1);
    copy[sizeof(copy) - 1] = '\0';

    char *saveptr;
    char *cmd = strtok_r(copy, ";", &saveptr);
    while (cmd != NULL) {
        char *expanded = expand_variables(cmd);
        add_history(expanded);
        execute_pipeline(expanded);
        cmd = strtok_r(NULL, ";", &saveptr);
    }
    return last_exit_code;
}

int run_script(const char *filename) {
    FILE *fp = fopen(filename, "r");
    if (!fp) {
        perror(filename);
        last_exit_code = 1;
        return 1;
    }
    char line[MAX_LINE_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\r\n")] = 0;
        process_line(line);
    }
    fclose(fp);
    return last_exit_code;
}

void load_rc_files(void) {
    if (access("/etc/mkshell.rc", R_OK) == 0) {
        run_script("/etc/mkshell.rc");
    }
    const char *home = getenv("HOME");
    if (home) {
        char user_rc[1024];
        snprintf(user_rc, sizeof(user_rc), "%s/.mkshellrc", home);
        if (access(user_rc, R_OK) == 0) {
            run_script(user_rc);
        }
    }
}

int main(int argc, char **argv) {
    signal(SIGINT, sigint_handler);

    if (argc > 1) {
        if (strcmp(argv[1], "-c") == 0 && argc > 2) {
            return process_line(argv[2]);
        }
        return run_script(argv[1]);
    }

    int is_interactive = isatty(STDIN_FILENO);
    if (is_interactive) {
        load_rc_files();
        printf("MKShell v%s — MIKE OS\n", MKSHELL_VERSION);
    }

    char line[MAX_LINE_LEN];
    while (1) {
        reap_background_jobs();
        if (is_interactive) {
            print_prompt();
        }
        if (is_interactive) {
            if (read_interactive_line(line, sizeof(line)) < 0) break;
        } else {
            if (!fgets(line, sizeof(line), stdin)) break;
            line[strcspn(line, "\r\n")] = 0;
        }
        process_line(line);
    }
    return last_exit_code;
}
