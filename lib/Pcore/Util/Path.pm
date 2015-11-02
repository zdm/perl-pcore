package Pcore::Util::Path;

use Pcore qw[-class];
use Storable qw[];
use Scalar::Util qw[blessed];    ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Util::URI;

use overload                     #
  q[""] => sub {
    return $_[0]->to_string;
  },
  q[cmp] => sub {
    my $self = shift;

    return $_[1] ? $_[0] cmp $self->to_string : $self->to_string cmp $_[0];
  },
  q[~~] => sub {
    my $self = shift;

    return $_[1] ? $_[0] ~~ $self->to_string : $self->to_string ~~ $_[0];
  },
  fallback => undef;

has to_string => ( is => 'lazy', clearer => '_clear_to_string', init_arg => undef );
has to_uri    => ( is => 'lazy', clearer => '_clear_to_uri',    init_arg => undef );

has lazy    => ( is => 'ro',   default  => 0 );
has is_abs  => ( is => 'ro',   required => 1 );
has is_dir  => ( is => 'lazy', init_arg => undef );
has is_file => ( is => 'lazy', init_arg => undef );

has volume    => ( is => 'ro',   default  => q[] );
has path      => ( is => 'ro',   required => 1 );                        # contains normalized path with volume
has canonpath => ( is => 'lazy', isa      => Str, init_arg => undef );

has dirname       => ( is => 'lazy', isa => Str, init_arg => undef );
has filename      => ( is => 'lazy', isa => Str, init_arg => undef );
has filename_base => ( is => 'lazy', isa => Str, init_arg => undef );
has suffix        => ( is => 'lazy', isa => Str, init_arg => undef );

has default_mime_type => ( is => 'lazy', isa => Str, default => 'application/octet-stream' );
has mime_type         => ( is => 'lazy', isa => Str );
has mime_category     => ( is => 'lazy', isa => Str );

around new => sub ( $orig, $self, $path = q[], @ ) {
    my %args = (
        is_dir   => 0,
        mswin    => $MSWIN,
        base     => q[],
        lazy     => 0,
        from_uri => 0,
        @_[ 3 .. $#_ ],
    );

    $self = ref $self if blessed $self;

    my $path_args = {
        path   => $path,
        volume => q[],
        is_abs => 0,
        lazy   => $args{lazy},
    };

    # speed optimizations
    if ( $path_args->{path} eq q[] ) {
        if ( $args{base} eq q[] ) {
            return bless {
                path   => q[],
                volume => q[],
                is_abs => 0,
              },
              $self;
        }
        else {
            $path_args->{path} = delete $args{base};
        }
    }
    elsif ( $path_args->{path} eq q[/] ) {
        return bless {
            path   => q[/],
            volume => q[],
            is_abs => 1,
          },
          $self;
    }

    # unescape and decode URI
    if ( $args{from_uri} && !ref $path_args->{path} ) {
        $path_args->{path} = URI::Escape::XS::decodeURIComponent( $path_args->{path} );

        utf8::decode( $path_args->{path} );
    }

    # convert "\" to "/"
    $path_args->{path} =~ s[\\+][/]smgo;

    # convert "//" -> "/"
    $path_args->{path} =~ s[/{2,}][/]smgo;

    # parse MSWIN volume
    if ( $args{mswin} ) {
        if ( $args{from_uri} ) {
            if ( $path_args->{path} =~ s[\A/([[:alpha:]]):/][/]smio ) {
                $path_args->{volume} = lc $1;

                $path_args->{is_abs} = 1;
            }
        }
        elsif ( $path_args->{path} =~ s[\A([[:alpha:]]):/][/]smio ) {
            $path_args->{volume} = lc $1;

            $path_args->{is_abs} = 1;
        }
    }

    # detect if path is absolute
    $path_args->{is_abs} = 1 if substr( $path_args->{path}, 0, 1 ) eq q[/];

    # add trailing "/" if path marked as dir
    $path_args->{path} .= q[/] if $args{is_dir} && substr( $path_args->{path}, -1, 1 ) ne q[/];

    # inherit from base path
    if ( defined $args{base} && $args{base} ne q[] && !$path_args->{is_abs} ) {

        # create base path object
        $args{base} = $self->new( $args{base}, mswin => $args{mswin}, from_uri => $args{from_uri} ) if !ref $args{base};

        # inherit base path attributes
        $path_args->{is_abs} = $args{base}->{is_abs};

        if ( $args{base}->{volume} ) {
            $path_args->{volume} = $args{base}->{volume};

            # remove volume from base path dirname
            $path_args->{path} = $args{base}->dirname =~ s[\A[[:alpha:]]:][]smor . $path_args->{path};
        }
        else {
            $path_args->{path} = $args{base}->dirname . $path_args->{path};
        }
    }

    # normalize, remove dot segments
    if ( index( $path_args->{path}, q[.] ) > -1 ) {

        # perform full normalization only if path contains "."
        my @segments;

        my @split = split m[/]smo, $path_args->{path};

        for my $seg (@split) {
            next if $seg eq q[] || $seg eq q[.];

            if ( $seg eq q[..] ) {
                if ( !$path_args->{is_abs} ) {
                    if ( !@segments || $segments[-1] eq q[..] ) {
                        push @segments, $seg;
                    }
                    else {
                        pop @segments;
                    }
                }
                else {
                    pop @segments;
                }
            }
            else {
                push @segments, $seg;
            }
        }

        # add leading "/" for abs path
        unshift @segments, q[] if $path_args->{is_abs};

        # preserve last "/"
        push @segments, q[] if substr( $path_args->{path}, -1, 1 ) eq q[/] || $split[-1] eq q[.] || $split[-1] eq q[..];

        # concatenate path segments
        $path_args->{path} = join q[/], @segments;
    }

    # add volume
    $path_args->{path} = $path_args->{volume} . q[:] . $path_args->{path} if $path_args->{volume};

    return bless $path_args, $self;
};

no Pcore;

our $MIME_TYPES;

# Pcore::Util interface
sub NEW {
    shift;

    return __PACKAGE__->new(@_);
}

sub _build_to_string ($self) {
    my $path = $self->path;

    if ( $self->{lazy} ) {
        $self->{lazy} = 0;

        if ( $self->is_dir && !-d $path ) {
            P->file->mkpath($path);
        }
        elsif ( $self->is_file && !-f $path ) {
            P->file->mkpath( $self->dirname );

            P->file->touch($path);
        }
    }

    return $path;
}

sub _build_to_uri ($self) {
    my $uri;

    $uri .= q[/] if $self->volume;

    $uri .= $self->path;

    utf8::encode($uri) if utf8::is_utf8($uri);

    # http://tools.ietf.org/html/rfc3986#section-3.3
    $uri =~ s/([$Pcore::Util::URI::ESCAPE_RE])/$Pcore::Util::URI::ESC_CHARS->{$1}/smgo;

    return $uri;
}

sub _build_is_dir ($self) {

    # empty path is dir
    return 1 if $self->path eq q[];

    # is dir if path ended with "/"
    return substr( $self->path, -1, 1 ) eq q[/] ? 1 : 0;
}

sub _build_is_file ($self) {
    return !$self->is_dir;
}

sub _build_dirname ($self) {
    return substr $self->path, 0, rindex( $self->path, q[/] ) + 1;
}

sub _build_filename ($self) {
    return q[] if $self->path eq q[];

    return substr $self->path, rindex( $self->path, q[/] ) + 1;
}

sub _build_filename_base ($self) {
    if ( $self->filename ne q[] ) {
        if ( ( my $idx = rindex $self->filename, q[.] ) > 0 ) {
            return substr $self->filename, 0, $idx;
        }
        else {
            return $self->filename;
        }
    }

    return q[];
}

sub _build_suffix ($self) {
    if ( $self->filename ne q[] ) {
        if ( ( my $idx = rindex $self->filename, q[.] ) > 0 ) {
            return substr $self->filename, $idx + 1;
        }
    }

    return q[];
}

# path without trailing "/"
sub _build_canonpath ($self) {
    return q[] if $self->path eq q[];

    return q[/] if $self->path eq q[/];

    return $self->path if $self->volume && $self->path eq $self->volume . q[:/];

    if ( $self->is_dir ) {
        return substr $self->path, 0, -1;
    }
    else {
        return $self->path;
    }
}

sub clone ($self) {
    return Storable::dclone($self);
}

sub realpath ($self) {
    if ( $self->is_dir && -d $self->path ) {
        return $self->new( Cwd::realpath( $self->path ), is_dir => 1 );    # Cwd::realpath always return path without trailing "/"
    }
    elsif ( $self->is_file && -f $self->path ) {
        return $self->new( Cwd::realpath( Cwd::realpath( $self->path ) ) );
    }
    else {
        return;
    }
}

# return new path object
sub to_abs ( $self, $abs_path = q[.] ) {
    if ( $self->is_abs ) {
        return $self->clone;
    }
    else {
        return $self->new( $self->to_string, base => $abs_path );
    }
}

sub parent ($self) {
    if ( $self->dirname ) {
        my $parent = $self->new( $self->dirname . q[../] );

        return $parent if $parent ne $self->to_string;
    }

    return;
}

sub is_root ($self) {
    if ( $self->is_abs ) {
        if ( $self->volume && $self->dirname eq $self->volume . q[:/] ) {
            return 1;
        }
        elsif ( $self->dirname eq q[/] ) {
            return 1;
        }
    }

    return;
}

# MIME
sub _mime_types {
    my $self = shift;

    unless ($MIME_TYPES) {
        $MIME_TYPES = P->cfg->load( $P->{SHARE_DIR} . 'mime.perl' );

        # index MIME categories
        for my $suffix ( keys $MIME_TYPES->{suffix}->%* ) {
            unless ( ref $MIME_TYPES->{suffix}->{$suffix} eq 'HASH' ) {
                $MIME_TYPES->{suffix}->{$suffix} = { type => $MIME_TYPES->{suffix}->{$suffix}, };
            }

            $MIME_TYPES->{category}->{ $MIME_TYPES->{suffix}->{$suffix}->{type} } = $MIME_TYPES->{suffix}->{$suffix}->{category} if $MIME_TYPES->{suffix}->{$suffix}->{category};
        }
    }

    return $MIME_TYPES;
}

sub _build_mime_type {
    my $self = shift;

    if ( $self->is_file ) {
        return $self->_mime_types->{suffix}->{ lc $self->suffix }->{type} // $self->default_mime_type;
    }
    else {
        return q[];
    }
}

sub _build_mime_category {
    my $self = shift;

    if ( $self->mime_type ) {
        return $self->_mime_types->{category}->{ $self->mime_type } // q[];
    }
    else {
        return q[];
    }
}

# INTERNALS
sub TO_DUMP {
    my $self = shift;

    my $res;
    my $tags;

    $res = q[path: "] . $self->path . q["];
    $res .= qq[\nMIME type: "] . $self->mime_type . q["] if $self->mime_type;

    return $res, $tags;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 1                    │ Modules::ProhibitExcessMainComplexity - Main code has high complexity score (39)                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 351                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
