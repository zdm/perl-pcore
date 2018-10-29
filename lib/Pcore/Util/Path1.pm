package Pcore::Util::Path1;

use Pcore -class, -const, -res;
use Clone qw[];
use Cwd qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Util::Data qw[from_uri_utf8 to_uri_path];
use Pcore::Util::Scalar qw[is_blessed_hashref];
use Pcore::Util::Text qw[encode_utf8 decode_utf8];

use overload
  q[""]  => sub { $_[0]->{path} },
  'bool' => sub {1},
  '.'    => sub {

    # $str + $self
    if ( $_[2] ) {
        return $_[0]->new("$_[1]/$_[0]->{path}");
    }

    # $self + $str
    else {
        return $_[0]->new("$_[0]->{path}/$_[1]");
    }
  },
  '-X' => sub {
    state $map = { map { $_ => eval qq[sub { return -$_ \$_[0] }] } qw[r w x o R W X O e z s f d l p S b c t u g k T B M A C] };    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]

    return $map->{ $_[1] }->( $MSWIN ? $_[0]->encoded : $_[0]->{path} );
  },
  fallback => 1;

with qw[
  Pcore::Util::Path::MIME
  Pcore::Util::Path::Dir
  Pcore::Util::Path::File
  Pcore::Util::Path::Poll
];

has path          => ( required => 1 );
has volume        => ( required => 1 );
has dirname       => ( required => 1 );
has filename      => ( required => 1 );
has filename_base => ( required => 1 );
has suffix        => ( required => 1 );

has is_abs => ();

has _encoded => ( init_arg => undef );    # utf8 encoded path
has _to_url  => ( init_arg => undef );

has IS_PCORE_PATH => ( 1, init_arg => undef );

# from_uri, from_mswin
around new => sub ( $orig, $self, $path = undef, %args ) {
    $self = ref $self if is_blessed_hashref $self;

    if ( !defined $path ) {
        return bless { path => '.' }, $self;
    }

    if ( is_blessed_hashref $path ) {
        return $path->clone if $path->{IS_PCORE_PATH};

        $path = "$path";
    }

    if ( $args{from_uri} ) {
        $path = from_uri_utf8 $path;
    }
    elsif ( $args{from_mswin} ) {
        $path = $self->decode($path);
    }

    return bless _parse($path), $self;
};

sub encoded ( $self ) {
    if ( !exists $self->{_encoded} ) {
        if ($MSWIN) {
            state $enc = Encode::find_encoding($Pcore::WIN_ENC);

            if ( utf8::is_utf8 $self->{path} ) {
                $self->{_encoded} = $enc->encode( $self->{path}, Encode::LEAVE_SRC & Encode::DIE_ON_ERR );
            }
            else {
                $self->{_encoded} = $self->{path};
            }
        }
        else {
            $self->{_encoded} = encode_utf8 $self->{path};
        }
    }

    return $self->{_encoded};
}

sub decode ( $self, $path ) {

    # already decoded
    return $path if utf8::is_utf8 $path;

    if ($MSWIN) {
        state $enc = Encode::find_encoding($Pcore::WIN_ENC);

        return $enc->decode( $path, Encode::LEAVE_SRC & Encode::DIE_ON_ERR );
    }
    else {
        return decode_utf8 $path;
    }
}

sub to_string ($self) { return $self->{path} }

sub clone ($self) { return Clone::clone($self) }

# TODO empty
sub to_uri ($self) {
    if ( !exists $self->{_to_uri} ) {
        my $path = $self->{path};

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

sub to_abs ( $self, $base = undef ) {

    # path is already absolute
    return defined wantarray ? $self->clone : () if $self->{is_abs};

    if ( !defined $base ) {
        $base = Cwd::getcwd();
    }
    else {
        $base = $self->new($base)->to_abs->{path};
    }

    if ( defined wantarray ) {
        return $self->new("$base/$self->{path}");
    }
    else {
        $self->path("$base/$self->{path}");

        return;
    }
}

# TODO
sub to_rel ( $self, $base = undef ) {
    ...;

    return;
}

sub to_realpath ( $self ) {
    my $realpath = Cwd::realpath( $self->{path} );

    if ( defined wantarray ) {
        return $self->new($realpath);
    }
    else {
        $self->path($realpath);

        return;
    }
}

sub _clear_cache ($self) {
    delete $self->@{qw[_encoded _to_uri]};

    return;
}

# SETTERS
sub path ( $self, $path = undef ) {
    if ( @_ > 1 ) {
        my $hash = _parse($path);

        $self->@{ keys $hash->%* } = values $hash->%*;

        $self->_clear_cache;
    }

    return $self->{path};
}

sub volume ( $self, $volume = undef ) {
    if ( @_ > 1 ) {
        my $path;

        if ( $self->{volume} ) {
            $path = $self->{path};

            substr $path, 0, 1, $volume;
        }
        else {
            $path = "$volume:/$self->{path}";
        }

        $self->path($path);
    }

    return $self->{volume};
}

sub dirname ( $self, $dirname = undef ) {
    if ( @_ > 1 ) {
        $self->path( defined $self->{filename} ? "$dirname/$self->{filename}" : $dirname );
    }

    return $self->{dirname};
}

sub filename ( $self, $filename = undef ) {
    if ( @_ > 1 ) {
        $self->path( defined $self->{dirname} ? "$self->{dirname}/$filename" : $filename );
    }

    return $self->{filename};
}

sub filename_base ( $self, $filename_base = undef ) {
    if ( @_ > 1 ) {
        my $path = '';

        $path .= "$self->{dirname}/" if defined $self->{dirname};

        $path .= $filename_base;

        $path .= ".$self->{suffix}" if defined $self->{suffix};

        $self->path($path);
    }

    return $self->{filename_base};
}

sub suffix ( $self, $suffix = undef ) {
    if ( @_ > 1 ) {
        die if !defined $self->{filename_base};

        my $path = '';

        $path .= "$self->{dirname}/" if defined $self->{dirname};

        $path .= "$self->{filename_base}.$suffix";

        $self->path($path);
    }

    return $self->{suffix};
}

sub TO_DUMP1 ( $self, @ ) {
    my $res;
    my $tags;

    $res = qq[path: "$self->{path}"];

    # $res .= qq[\nMIME type: "] . $self->mime_type . q["] if $self->mime_type;

    return $res, $tags;
}

use Inline(
    C => <<'C',
# include "Pcore/Util/Path.h"

SV *_parse (SV *path) {

    // call fetch() if a tied variable to populate the SV
    SvGETMAGIC(path);

    const char *buf = NULL;
    size_t buf_len = 0;

    // check for undef
    if ( path != &PL_sv_undef ) {

        // copy the sv without the magic struct
        buf = SvPV_nomg_const(path, buf_len);
    }

    PcoreUtilPath *res = parse(buf, buf_len);

    HV *hash = newHV();
    hv_store(hash, "is_abs", 6, newSVuv(res->is_abs), 0);

    // path
    SV *path_sv = newSVpvn(res->path, res->path_len);
    sv_utf8_decode(path_sv);
    hv_store(hash, "path", 4, path_sv, 0);

    // volume
    hv_store(hash, "volume", 6, res->volume_len ? newSVpvn(res->volume, res->volume_len) : newSV(0), 0);

    // dirname
    /* if (res->path_len) { */
    /*     SV *path = newSVpvn(res->path, res->path_len); */
    /*     sv_utf8_decode(path); */
    /*     hv_store(hash, "path", 7, path, 0); */
    /* } */
    /* else { */
    /*     hv_store(hash, "dirname", 7, newSV(0), 0); */
    /* } */

    destroyPcoreUtilPath(res);

    sv_2mortal((SV*)newRV_noinc((SV *)hash));

    return newRV((SV *)hash);
}
C
    inc        => '-I' . $ENV->{share}->get_storage( 'Pcore', 'include' ),
    ccflagsex  => '-Wall -Wextra -Ofast -std=c11',
    prototypes => 'ENABLE',
    prototype  => { _parse => '$', },

    # build_noisy => 1,
    # force_build => 1,
);

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 26                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 167                  | ControlStructures::ProhibitYadaOperator - yada operator (...) used                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 241, 259             | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
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
