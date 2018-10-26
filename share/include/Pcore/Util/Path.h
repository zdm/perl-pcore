# ifndef PCORE_UTIL_PATH_H
# define PCORE_UTIL_PATH_H

struct PcoreUtilPath {

    // path
    size_t path_len;
    U8 *path;

    // is_abs
    int is_abs;

    // volume
    size_t volume_len;
    U8 *volume;
};

SV *normalize (U8 *buf, size_t buf_len);

# include "Pcore/Util/Path.c"

# endif
