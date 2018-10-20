package Pcore::Util::Path1;

use Pcore -class, -const, -res;
use Clone qw[];
use Cwd qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Util::Data qw[from_uri_utf8 to_uri_path];
use Pcore::Util::Scalar qw[is_blessed_hashref];

use overload
  q[""]    => sub { $_[0]->{to_string} },
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

    $self = bless { to_string => $path }, __PACKAGE__;

    if ($MSWIN) {
        if ( $path =~ /\A([a-z]):/smi ) {
            $self->{volume} = lc $1;
            $self->{is_abs} = 1;
        }
    }
    else {
        if ( substr( $path, 0, 1 ) eq '/' ) {
            $self->{is_abs} = 1;
        }
    }

    return $self;
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

use Inline(
    C => <<'C',
# include <string.h>

struct Tokens {
    size_t len;
    int is_dots;
    U8 *token;
};

SV *normalize_path (SV *path) {

    /* call fetch() if a tied variable to populate the sv */
    SvGETMAGIC(path);

    /* check for undef */
    if ( path == &PL_sv_undef ) return newSV(0);

    U8 *src;
    size_t src_len;

    /* copy the sv without the magic struct */
    src = SvPV_nomg_const(path, src_len);

    // TODO round / 2
    struct Tokens tokens [ src_len ];
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

                        tokens_len -= 1;
                        tokens_total_len -= tokens[tokens_len - 1].len;
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

    // TODO calculate result length
    size_t result_len = prefix_len + tokens_total_len + tokens_len - 1;

    // create result SV
    SV *result = newSV( result_len );
    SvPOK_on(result);

    // set the current length of result
    SvCUR_set( result, result_len );

    // get pointer to the result buffer
    U8 *dst = (U8 *)SvPV_nolen(result);
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

        // TODO
        if (i < tokens_len) {
            dst[dst_pos++] = '/';
        }
    }

    // decode result to utf8
    sv_utf8_decode(result);

    return result;
}

C
    ccflagsex  => '-Wall -Wextra -Ofast -std=c11',
    prototypes => 'ENABLE',
    prototype  => { normalize_path => '$', },
);

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 34                   | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 46                   | RegularExpressions::ProhibitEnumeratedClasses - Use named character classes ([a-z] vs. [[:lower:]])            |
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
