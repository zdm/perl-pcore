package Pcore::Util::Path1;

use Pcore -class, -const, -res;
use Clone qw[];
use Cwd qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Util::Data qw[from_uri_utf8 to_uri_path];
use Pcore::Util::Scalar qw[is_blessed_hashref];

use overload
  q[""]  => sub { $_[0]->{to_string} },
  'bool' => sub {1},
  '.' => sub ( $self, $str, $order ) {

    # $str + $self
    if ($order) {
        return Pcore::Util::Path1->new("$str/$self->{to_string}");
    }

    # $self + $str
    else {
        if ( $self->{to_string} eq '' ) {
            return Pcore::Util::Path1->new("./$str");
        }
        else {
            return Pcore::Util::Path1->new("$self->{to_string}/$str");
        }
    }
  },
  fallback => 1;

with qw[
  Pcore::Util::Result::Status
  Pcore::Util::Path1::Dir
  Pcore::Util::Path1::Poll
];

has to_string     => ();
has volume        => ();
has dirname       => ();
has filename      => ();
has filename_base => ();
has suffix        => ();

has is_abs => ();

has _to_url => ( init_arg => undef );

has IS_PCORE_PATH => ( 1, init_arg => undef );

around new => sub ( $orig, $self, $path = undef, %args ) {
    if ( !defined $path ) {
        return bless { to_string => '' }, $self;
    }

    if ( is_blessed_hashref $path ) {
        return $path if $path->{IS_PCORE_PATH};

        $path = "$path";
    }

    if ( $args{from_uri} ) {
        $path = from_uri_utf8 $path;
    }

    return bless _normalize($path), $self;
};

sub to_string ($self) {
    if ( !exists $self->{to_string} ) {

    }

    return $self->{to_string};
}

sub clone ($self) {
    return Clone::clone($self);
}

sub to_uri ($self) {
    if ( !exists $self->{_to_uri} ) {
        my $path = $self->{to_string};

        # Relative Reference: https://tools.ietf.org/html/rfc3986#section-4.2
        # A path segment that contains a colon character (e.g., "this:that")
        # cannot be used as the first segment of a relative-path reference, as
        # it would be mistaken for a scheme name.  Such a segment must be
        # preceded by a dot-segment (e.g., "./this:that") to make a relative-
        # path reference.
        # $path = "./$path" if $path =~ m[\A[^/]*:]sm;

        if ( $self->{volume} ) {
            $self->{_to_uri} = to_uri_path "/$path";
        }
        elsif ( $path =~ m[\A[^/]*:]sm ) {
            $self->{_to_uri} = to_uri_path "./$path";
        }
        else {
            $self->{_to_uri} = to_uri_path $path;
        }
    }

    return $self->{_to_uri};
}

# TODO error on empty path
sub to_abs ( $self, $base = undef ) {

    # path is already absolute
    return defined wantarray ? $self->clone : () if $self->{is_abs};

    if ( !defined $base ) {
        $base = Cwd::getcwd();
    }
    else {
        $base = $self->new($base)->to_abs->{to_string};
    }

    if ( defined wantarray ) {
        return $self->new("$base/$self->{to_string}");
    }
    else {
        $self->{to_string} = "$base/$self->{to_string}";
    }

    return;
}

# TODO error on empty path
sub to_realpath ( $self ) {
    my $realpath = Cwd::realpath( $self->{to_string} );

    if ( defined wantarray ) {
        return $self->new($realpath);
    }
    else {
        $self->{to_string} = $realpath;

        return;
    }
}

sub volume ( $self, $volume = undef ) {
    return;
}

# sub TO_DUMP {
#     my $self = shift;

#     my $res;
#     my $tags;

#     $res = qq[path: "$self->{to_string}"];

#     # $res .= qq[\nMIME type: "] . $self->mime_type . q["] if $self->mime_type;

#     return $res, $tags;
# }

# TODO
# single function
# watch modification
use Inline(
    C => <<'C',
# include <string.h>

struct Tokens {
    size_t len;
    int is_dots;
    U8 *token;
};

struct Result {
    SV *is_abs;
    SV *path;
    SV *volume;
};

static struct Result __normalize (U8 *src, size_t src_len) {
    struct Tokens tokens [ (src_len / 2) + 1 ];

    size_t tokens_len = 0;
    size_t tokens_total_len = 0;

    U8 token[ src_len ];
    size_t token_len = 0;

    size_t prefix_len = 0;
    size_t i = 0;

    // parse leading windows volume
# ifdef WIN32
    U8 prefix[3];

    if ( src_len >= 2 && src[1] == ':' && ( src[2] == '/' || src[2] == '\\' ) && ( ( src[0] >= 97 && src[0] <= 122 ) || ( src[0] >= 65 && src[0] <= 90 ) ) ) {
        prefix[0] = tolower(src[0]);
        prefix[1] = ':';
        prefix[2] = '/';
        prefix_len = 3;
        i = 3;
    }

    // parse leading "/"
# else
    U8 prefix;

    if (src[0] == '/' || src[0] == '\\') {
        prefix = '/';
        prefix_len = 1;
        i = 1;
    }
# endif

    for ( i; i < src_len; i++ ) {
        int process_token = 0;

        // slash char
        if ( src[i] == '/' || src[i] == '\\' ) {
            process_token = 1;
        }
        else {

            // add char to the current token
            token[ token_len++ ] = src[i];

            // last char
            if (i + 1 == src_len) {
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

    struct Result result;

    result.is_abs = prefix_len ? newSV(1) : newSV(1);
    result.path = path;
    result.volume = newSV(1);

    return result;
}

SV *_normalize (SV *path) {

    // call fetch() if a tied variable to populate the SV
    SvGETMAGIC(path);

    // check for undef
    if ( path == &PL_sv_undef ) return newSV(0);

    U8 *src;
    size_t src_len;

    // copy the sv without the magic struct
    src = SvPV_nomg_const(path, src_len);

    struct Result result = __normalize(src, src_len);

    HV *hash = newHV();
    hv_store(hash, "is_abs", 6, result.is_abs, 0);
    hv_store(hash, "to_string", 9, result.path, 0);
    hv_store(hash, "volume", 6, result.volume, 0);

    sv_2mortal((SV*)newRV_noinc((SV *)hash));

    return newRV((SV *)hash);;
}

C
    ccflagsex  => '-Wall -Wextra -Ofast -std=c11',
    prototypes => 'ENABLE',
    prototype  => { _normalize => '$', },
);

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 21, 52               | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path1

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
