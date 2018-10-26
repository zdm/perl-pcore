# include <string.h>
# include "Pcore/Util/Path.h"

struct Tokens {
    size_t len;
    int is_dots;
    U8 *token;
};

SV *normalize (U8 *buf, size_t buf_len) {
    struct Tokens tokens [ (buf_len / 2) + 1 ];

    size_t tokens_len = 0;
    size_t tokens_total_len = 0;

    U8 token[ buf_len ];
    size_t token_len = 0;

    size_t prefix_len = 0;
    size_t i = 0;

    // parse leading windows volume
# ifdef WIN32
    U8 prefix[3];

	/* TODO ( ( buf[0] >= 97 && buf[0] <= 122 ) || ( buf[0] >= 65 && buf[0] <= 90 ) ) */
    if ( buf_len >= 2 && buf[1] == ':' && ( buf[2] == '/' || buf[2] == '\\' ) && isalpha(buf[0]) ) {
        prefix[0] = tolower(buf[0]);
        prefix[1] = ':';
        prefix[2] = '/';
        prefix_len = 3;
        i = 3;
    }

    // parse leading "/"
# else
    U8 prefix;

    if (buf[0] == '/' || buf[0] == '\\') {
        prefix = '/';
        prefix_len = 1;
        i = 1;
    }
# endif

    for ( i; i < buf_len; i++ ) {
        int process_token = 0;

        // slash char
        if ( buf[i] == '/' || buf[i] == '\\' ) {
            process_token = 1;
        }
        else {

            // add char to the current token
            token[ token_len++ ] = buf[i];

            // last char
            if (i + 1 == buf_len) {
                process_token = 1;
            }
        }

        // current token is completed, process token
        if (process_token && token_len) {
            int skip_token = 0;
            int is_dots = 0;

            // skip "." token
            if ( token_len == 1 && token[0] == '.' ) {
                skip_token = 1;
            }

            // process ".." token
            else if ( token_len == 2 && token[0] == '.' && token[1] == '.' ) {
                is_dots = 1;

                // has previous token
                if (tokens_len) {

                    // previous token is NOT "..", remove previous token
                    if (!tokens[tokens_len - 1].is_dots) {
                        skip_token = 1;

                        tokens_total_len -= tokens[tokens_len - 1].len;

                        tokens_len -= 1;
                    }
                }

                // has no previous token
                else {

                    // path is absolute, skip ".." token
                    if (prefix_len) {
                        skip_token = 1;
                    }
                }
            }

            // store token
            if (!skip_token) {
                tokens[tokens_len].token = malloc(token_len);
                memcpy(tokens[tokens_len].token, token, token_len);

                tokens[tokens_len].len = token_len;
                tokens[tokens_len].is_dots = is_dots;

                tokens_total_len += token_len;
                tokens_len++;
            }

            token_len = 0;
        }
    }

    // calculate path length
    size_t path_len = prefix_len + tokens_total_len;
    if (tokens_len) {
        path_len += tokens_len - 1;
    }

    // create path SV
    SV *path = newSV( path_len + 1 );
    SvPOK_on(path);

    // set the current length of path
    SvCUR_set( path, path_len );

    // path is not empty
    if (path_len) {

        // get pointer to the path SV buffer
        U8 *dst = (U8 *)SvPV_nolen(path);
        size_t dst_pos = 0;

        // add prefix
        if (prefix_len) {
            dst_pos += prefix_len;
            memcpy(dst, &prefix, prefix_len);
        }

        // join tokens
        for ( size_t i = 0; i < tokens_len; i++ ) {
            memcpy(dst + dst_pos, tokens[i].token, tokens[i].len);
            free(tokens[i].token);

            dst_pos += tokens[i].len;

            // add "/" if token is not last
            if (i < tokens_len) {
                dst[dst_pos++] = '/';
            }
        }

        // decode path to utf8
        sv_utf8_decode(path);
    }

    HV *hash = newHV();
    hv_store(hash, "is_abs", 6, prefix_len ? newSVuv(1) : newSVuv(0), 0);
    hv_store(hash, "to_string", 9, path, 0);
    hv_store(hash, "volume", 6, prefix_len == 3 ? newSVpvn(&prefix, 1) : newSV(0), 0);

    sv_2mortal((SV*)newRV_noinc((SV *)hash));

    return newRV((SV *)hash);
}
