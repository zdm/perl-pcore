# ifndef PCORE_UTIL_PATH_H
# define PCORE_UTIL_PATH_H

typedef struct {

    // is_abs
    int is_abs;

    // path
    size_t path_len;
    char *path;

    // volume
    size_t volume_len;
    char *volume;
} PcoreUtilPath;

void destroyPcoreUtilPath (PcoreUtilPath *path);

PcoreUtilPath *parse (const char *buf, size_t buf_len);

# include "Pcore/Util/Path.c"

# endif
