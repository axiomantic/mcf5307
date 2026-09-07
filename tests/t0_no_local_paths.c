/* `t0_no_local_paths` - no shipped source file names a path that exists on one
 * machine.
 *
 * WHY A PROGRAM AND NOT A GREP. The scan has to exclude build output, and it
 * has to exclude it by a PROPERTY of a directory rather than by that
 * directory's NAME: a directory that holds `CMakeCache.txt` is build output,
 * whatever anyone called it. A `grep --exclude-dir=build` is a check whose
 * verdict depends on a name, and it passes on a tree configured into
 * `build2/` for a reason that has nothing to do with the property under test.
 * The excluded set is printed with the result, so a reader can see what was
 * not searched instead of assuming it was empty.
 *
 * WHY GENERATED OUTPUT INSIDE A SCANNED DIRECTORY IS A HIT AND NOT AN
 * EXCEPTION. The `CMakeCache.txt` property excludes a build tree. It does not
 * excuse a generated file a tool dropped beside its own source - a `.pyc`
 * records the path its source was compiled from, so invoking a generator by
 * an absolute path plants that path in the tree. The scan names it, which is
 * the correct report: output belongs in a build tree. Excusing it would need
 * an exclusion by NAME, which is the fault the property exists to avoid.
 *
 * WHY THE TWO NEEDLES ARE ASSEMBLED FROM CHARACTERS. This file lives inside
 * `tests/`, which is one of the directories the scan reads. Spelled as string
 * literals the needles would appear in the scanner's own source and the
 * scanner would report itself - the tool's own output becoming its input. The
 * characters are listed instead, so no offending sequence exists in this file
 * and the scan over `tests/` is a real scan rather than an exception.
 *
 * WHY IT REFUSES AN EMPTY DIRECTORY LIST. A scan of nothing reports no hit
 * and exits 0, which is indistinguishable from a clean tree. Every argument
 * must name a directory that exists, and a missing one is an error rather
 * than an empty result.
 *
 * usage: t0_no_local_paths <root> <dir>...
 */

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static const char NEEDLE_HOME[] = {'~', '/', '\0'};
static const char NEEDLE_ABS[] = {'/', 'U', 's', 'e', 'r', 's', '/', '\0'};

static const char *const NEEDLES[] = {NEEDLE_HOME, NEEDLE_ABS};
#define NEEDLE_COUNT (sizeof NEEDLES / sizeof NEEDLES[0])

#define TAG "t0_no_local_paths"

static size_t g_hits;

/* The excluded set, grown as directories are met and printed with the
 * result. */
static char **g_excluded;
static size_t g_excluded_len;

static void fatal(const char *what, const char *path) {
    fprintf(stderr, "%s: error: %s: %s\n", TAG, what, path);
    exit(2);
}

static char *xstrdup(const char *s) {
    char *copy = malloc(strlen(s) + 1u);
    if (copy == NULL) {
        fatal("out of memory", s);
    }
    strcpy(copy, s);
    return copy;
}

static char *join(const char *left, const char *right) {
    size_t len = strlen(left) + 1u + strlen(right) + 1u;
    char *out = malloc(len);
    if (out == NULL) {
        fatal("out of memory", right);
    }
    if (left[0] == '\0') {
        snprintf(out, len, "%s", right);
    } else {
        snprintf(out, len, "%s/%s", left, right);
    }
    return out;
}

static int compare_strings(const void *a, const void *b) {
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static void record_excluded(const char *relative) {
    char **grown = realloc(g_excluded, (g_excluded_len + 1u) * sizeof *g_excluded);
    if (grown == NULL) {
        fatal("out of memory", relative);
    }
    g_excluded = grown;
    g_excluded[g_excluded_len] = xstrdup(relative);
    g_excluded_len++;
}

static int holds_cmake_cache(const char *absolute) {
    char *probe = join(absolute, "CMakeCache.txt");
    struct stat info;
    int found = (stat(probe, &info) == 0 && S_ISREG(info.st_mode));
    free(probe);
    return found;
}

/* Reads the whole file. Every file this scan reads is a source file, and a
 * rolling window would have to carry the longest needle across its own
 * boundary for no gain at this size. */
static char *slurp(const char *absolute, size_t *size_out) {
    FILE *handle = fopen(absolute, "rb");
    if (handle == NULL) {
        fatal("cannot open", absolute);
    }

    size_t capacity = 8192u;
    size_t used = 0u;
    char *buffer = malloc(capacity);
    if (buffer == NULL) {
        fclose(handle);
        fatal("out of memory", absolute);
    }

    for (;;) {
        if (used == capacity) {
            capacity *= 2u;
            char *grown = realloc(buffer, capacity);
            if (grown == NULL) {
                free(buffer);
                fclose(handle);
                fatal("out of memory", absolute);
            }
            buffer = grown;
        }
        size_t got = fread(buffer + used, 1u, capacity - used, handle);
        used += got;
        if (got == 0u) {
            break;
        }
    }

    if (ferror(handle)) {
        free(buffer);
        fclose(handle);
        fatal("cannot read", absolute);
    }
    fclose(handle);

    *size_out = used;
    return buffer;
}

static void scan_file(const char *absolute, const char *relative) {
    size_t size = 0u;
    char *text = slurp(absolute, &size);

    size_t line = 1u;
    for (size_t at = 0u; at < size; at++) {
        if (text[at] == '\n') {
            line++;
            continue;
        }
        for (size_t which = 0u; which < NEEDLE_COUNT; which++) {
            size_t needle_len = strlen(NEEDLES[which]);
            if (size - at < needle_len) {
                continue;
            }
            if (memcmp(text + at, NEEDLES[which], needle_len) == 0) {
                printf("%s: hit: %s:%zu: %s\n", TAG, relative, line,
                       NEEDLES[which]);
                g_hits++;
            }
        }
    }

    free(text);
}

static void walk(const char *absolute, const char *relative) {
    if (holds_cmake_cache(absolute)) {
        record_excluded(relative);
        return;
    }

    DIR *dir = opendir(absolute);
    if (dir == NULL) {
        fatal("cannot open directory", absolute);
    }

    char **names = NULL;
    size_t names_len = 0u;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char **grown = realloc(names, (names_len + 1u) * sizeof *names);
        if (grown == NULL) {
            closedir(dir);
            fatal("out of memory", absolute);
        }
        names = grown;
        names[names_len] = xstrdup(entry->d_name);
        names_len++;
    }
    closedir(dir);

    /* `readdir` order is the filesystem's, so the report would differ between
     * two machines holding identical trees. The sort makes the output a value
     * a caller can assert whole. */
    qsort(names, names_len, sizeof *names, compare_strings);

    for (size_t at = 0u; at < names_len; at++) {
        char *child_absolute = join(absolute, names[at]);
        char *child_relative = join(relative, names[at]);

        struct stat info;
        if (lstat(child_absolute, &info) != 0) {
            fatal("cannot stat", child_absolute);
        }
        if (S_ISDIR(info.st_mode)) {
            walk(child_absolute, child_relative);
        } else if (S_ISREG(info.st_mode)) {
            scan_file(child_absolute, child_relative);
        }
        /* A symbolic link is neither read nor followed: it resolves outside
         * the tree or it duplicates a file the walk already reaches. */

        free(child_absolute);
        free(child_relative);
        free(names[at]);
    }
    free(names);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <root> <dir>...\n", TAG);
        return 2;
    }

    const char *root = argv[1];

    printf("%s: scanned:", TAG);
    for (int at = 2; at < argc; at++) {
        printf(" %s", argv[at]);
    }
    printf("\n");

    for (int at = 2; at < argc; at++) {
        char *absolute = join(root, argv[at]);
        struct stat info;
        if (stat(absolute, &info) != 0 || !S_ISDIR(info.st_mode)) {
            fatal("not a directory", absolute);
        }
        walk(absolute, argv[at]);
        free(absolute);
    }

    qsort(g_excluded, g_excluded_len, sizeof *g_excluded, compare_strings);
    printf("%s: excluded:", TAG);
    if (g_excluded_len == 0u) {
        printf(" none");
    }
    for (size_t at = 0u; at < g_excluded_len; at++) {
        printf(" %s", g_excluded[at]);
        free(g_excluded[at]);
    }
    printf("\n");
    free(g_excluded);

    if (g_hits > 0u) {
        printf("%s: FAIL: %zu hit(s)\n", TAG, g_hits);
        return 1;
    }
    printf("%s: PASS: no machine-local path\n", TAG);
    return 0;
}
