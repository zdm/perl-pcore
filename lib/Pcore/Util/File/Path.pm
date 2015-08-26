package Pcore::Util::File::Path;

use Pcore qw[-class];
use Storable qw[];
use URI::Escape::XS qw[];    ## no critic qw[Modules::ProhibitEvilModules]

use overload                 #
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

has lazy    => ( is => 'rwp',  default  => 0 );
has is_abs  => ( is => 'ro',   required => 1 );
has is_dir  => ( is => 'lazy', init_arg => undef );
has is_file => ( is => 'lazy', init_arg => undef );

has volume    => ( is => 'ro',   default  => q[] );
has _path     => ( is => 'ro',   required => 1 );                        # contains normalized path with volume
has canonpath => ( is => 'lazy', isa      => Str, init_arg => undef );

has dirname       => ( is => 'lazy', isa => Str, init_arg => undef );
has filename      => ( is => 'lazy', isa => Str, init_arg => undef );
has filename_base => ( is => 'lazy', isa => Str, init_arg => undef );
has suffix        => ( is => 'lazy', isa => Str, init_arg => undef );

has default_mime_type => ( is => 'lazy', isa => Str, default => 'application/octet-stream' );
has mime_type         => ( is => 'lazy', isa => Str );
has mime_category     => ( is => 'lazy', isa => Str );

no Pcore;

our $MIME_TYPES;

sub NEW {
    my $self = shift;
    my $path = shift;
    my %args = (
        is_dir => undef,
        mswin  => $MSWIN,
        base   => undef,
        @_,
        is_abs => 0,
        volume => undef,
    );

    undef $path if defined $path && $path eq q[];

    undef $args{base} if defined $args{base} && $args{base} eq q[];

    # speed optimizations
    if ( !defined $path ) {
        if ( defined $args{base} ) {
            $path = delete $args{base};
        }
        else {
            return bless {
                _path  => q[],
                is_abs => 0,
              },
              __PACKAGE__;
        }
    }

    if ( $path eq q[/] ) {
        return bless {
            _path  => q[/],
            is_abs => 1,
          },
          __PACKAGE__;
    }

    # convert "\" to "/"
    $path =~ s[\\+][/]smg if index( $path, q[\\] ) != -1;

    # parse windows volume, /c:/, c:/ -> /
    if ( $args{mswin} && $path =~ s[\A/?([[:alpha:]]):(?:/|\z)][/]sm ) {
        $args{volume} = lc $1;

        $args{is_abs} = 1;
    }

    # inherit from base path
    if ( !$args{is_abs} && defined $args{base} ) {

        # path is already absolute
        if ( substr( $path, 0, 1 ) eq q[/] ) {
            $args{_path} = $path;

            $args{is_abs} = 1;
        }
        else {
            # convert base path "\" to "/"
            $args{base} =~ s[\\+][/]smg if index( $args{base}, q[\\] ) != -1;

            # parse windows volume, /c:/, c:/ -> /
            if ( $args{mswin} && $args{base} =~ s[\A/?([[:alpha:]]):(?:/|\z)][/]sm ) {
                $args{volume} = lc $1;

                $args{is_abs} = 1;
            }

            # merge with base path
            $args{_path} = substr( $args{base}, 0, rindex( $args{base}, q[/] ) + 1 ) . $path;
        }
    }
    else {
        $args{_path} = $path;
    }

    # detect if path is absolute
    $args{is_abs} = 1 if !$args{is_abs} && substr( $args{_path}, 0, 1 ) eq q[/];

    # add trailing "/" if path marked as dir
    $args{_path} .= q[/] if $args{is_dir};

    # normalize
    if ( index( $args{_path}, q[.] ) == -1 ) {

        # convert "//" -> "/"
        $args{_path} =~ s[/{2,}][/]smg;
    }
    else {
        # perform full normalization only if path contains "."
        my @segments;

        my @split = split m[/]sm, $args{_path};

        for my $seg ( grep { $_ ne q[] && $_ ne q[.] } @split ) {
            if ( $seg eq q[..] ) {
                if ( !$args{is_abs} ) {
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

        # preserve last "/"
        push @segments, q[] if substr( $args{_path}, -1 ) eq q[/] || $split[-1] eq q[.] || $split[-1] eq q[..];

        # concatenate path segments, add leading "/" for abs path
        $args{_path} = ( $args{is_abs} ? q[/] : q[] ) . join q[/], @segments;
    }

    # add volume
    $args{_path} = $args{volume} . q[:] . $args{_path} if $args{volume};

    return __PACKAGE__->new( \%args );
}

sub _build_to_string ($self) {
    my $path = $self->_path;

    if ( $self->lazy ) {
        $self->_set_lazy(0);

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

    $uri .= $self->_path;

    # http://tools.ietf.org/html/rfc3986#section-3.3
    return URI::Escape::XS::uri_escape( $uri, q[^[:alnum:].\-_~!$&'()*+,;=:@/] );
}

sub _build_is_dir ($self) {

    # empty path is dir
    return 1 if $self->_path eq q[];

    # is dir if path ended with "/"
    return substr( $self->_path, -1, 1 ) eq q[/] ? 1 : 0;
}

sub _build_is_file ($self) {
    return !$self->is_dir;
}

sub _build_dirname ($self) {
    return substr $self->_path, 0, rindex( $self->_path, q[/] ) + 1;
}

sub _build_filename ($self) {
    return q[] if $self->_path eq q[];

    return substr $self->_path, rindex( $self->_path, q[/] ) + 1;
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
    return q[] if $self->_path eq q[];

    return q[/] if $self->_path eq q[/];

    return $self->_path if $self->volume && $self->_path eq $self->volume . q[:/];

    if ( $self->is_dir ) {
        return substr $self->_path, 0, -1;
    }
    else {
        return $self->_path;
    }
}

sub clone ($self) {
    return Storable::dclone($self);
}

sub realpath ($self) {
    if ( $self->is_dir && -d $self->_path ) {
        return $self->NEW( Cwd::realpath( $self->_path ), is_dir => 1 );    # Cwd::realpath always return path without trailing "/"
    }
    elsif ( $self->is_file && -f $self->_path ) {
        return $self->NEW( Cwd::realpath( Cwd::realpath( $self->_path ) ) );
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
        return $self->NEW( $self->to_string, base => $abs_path );
    }
}

sub parent ($self) {
    if ( $self->dirname ) {
        my $parent = $self->NEW( $self->dirname . q[../] );

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
        for my $suffix ( keys $MIME_TYPES->{suffix} ) {
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

    $res = q[path: "] . $self->_path . q["];
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
## │    3 │ 48                   │ Subroutines::ProhibitExcessComplexity - Subroutine "NEW" with high complexity score (39)                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 201                  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File::Path

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
