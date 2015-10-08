package Pcore::Util::URI;

use Pcore qw[-class];

use Pcore qw[-class];
use Pcore::Util::URI::Host;
use Pcore::Util::File::Path;
use Const::Fast qw[const];
use URI::_idna qw[];
use URI::Escape::XS qw[];    ## no critic qw[Modules::ProhibitEvilModules]

use overload                 #
  q[""] => sub {
    return $_[0]->to_string;
  },
  q[cmp] => sub {
    return $_[0]->to_string cmp $_[1];
  },
  q[bool] => sub {
    return 1;
  },
  fallback => undef;

has scheme   => ( is => 'ro' );    # ASCII
has userinfo => ( is => 'ro' );    # escaped, ASCII
has host     => ( is => 'ro' );
has port     => ( is => 'ro' );    # punycoded, ASCII
has path     => ( is => 'ro' );
has query    => ( is => 'ro' );    # escaped, ASCII
has fragment => ( is => 'ro' );    # escaped, ASCII

has to_string => ( is => 'lazy', init_arg => undef );
has canon     => ( is => 'lazy', init_arg => undef );

has authority    => ( is => 'lazy', init_arg => undef );    # escaped, ASCII, punycoded host
has userinfo_b64 => ( is => 'lazy', init_arg => undef );    # ASCII
has username     => ( is => 'lazy', init_arg => undef );    # unescaped, ASCII
has password     => ( is => 'lazy', init_arg => undef );    # unescaped, ASCII
has hostport     => ( is => 'lazy', init_arg => undef );    # punycoded, ASCII

has path_canon => ( is => 'lazy', init_arg => undef );

has scheme_is_valid => ( is => 'lazy', init_arg => undef );

has is_secure => ( is => 'lazy', default => 0, init_arg => undef );

has default_port => ( is => 'lazy', default => 0, init_arg => undef );
has connect_port => ( is => 'lazy', init_arg => undef );
has connect      => ( is => 'lazy', init_arg => undef );

around new => sub ( $orig, $self, $uri, @ ) {
    my %args = (
        base      => undef,
        authority => undef,
        @_[ 3 .. $#_ ],
    );

    my $uri_args = $self->_parse_uri_string( $uri, $args{authority} );

    my $scheme = $uri_args->{scheme};

    # parse base scheme
    if ( $uri_args->{scheme} eq q[] && $args{base} ) {
        if ( ref $args{base} ) {
            $scheme = $args{base}->scheme;
        }
        else {
            my $first_colon_idx = index $args{base}, q[:];

            if ( $first_colon_idx != -1 ) {
                my $first_slash_idx = index $args{base}, q[/];

                $scheme = lc substr $args{base}, 0, $first_colon_idx if $first_colon_idx < $first_slash_idx;
            }
        }
    }

    state $scheme_cache = {    #
        q[] => undef,
    };

    if ( !exists $scheme_cache->{$scheme} ) {
        try {
            $scheme_cache->{$scheme} = P->class->load( $scheme, ns => 'Pcore::Util::URI' );
        }
        catch {
            $scheme_cache->{$scheme} = undef;
        };
    }

    $self = $scheme_cache->{$scheme} if $scheme_cache->{$scheme};

    return $self->_new( $uri_args, \%args );
};

no Pcore;

# http://tools.ietf.org/html/rfc3986#section-2.2
const our $UNRESERVED          => '0-9a-zA-Z' . quotemeta q[-._~];
const our $RESERVED_GEN_DELIMS => quotemeta q[:/?#[]@];
const our $RESERVED_SUB_DELIMS => quotemeta q[!$&'()*+,;=];
const our $ESCAPE_RE           => qq[^${UNRESERVED}${RESERVED_GEN_DELIMS}${RESERVED_SUB_DELIMS}%];
const our $ESC_CHARS           => { map { chr $_ => sprintf '%%%02X', $_ } ( 0 .. 255 ) };

# Pcore::Util interface
sub NEW {
    shift;

    return __PACKAGE__->new(@_);
}

sub _new ( $self, $uri_args, $args ) {
    $uri_args->{host} = bless { name => $uri_args->{host} }, 'Pcore::Util::URI::Host';

    delete $uri_args->{_has_authority};

    return if $args->{no_bless};

    return bless $uri_args, $self;
}

sub _parse_uri_string ( $self, $uri, $with_authority = 0 ) {
    my %args = (
        _has_authority => 0,
        scheme         => q[],
        userinfo       => q[],
        host           => q[],
        port           => 0,
        path           => q[],
        query          => q[],
        fragment       => q[],
    );

    utf8::encode($uri) if utf8::is_utf8($uri);

    # scheme
    {
        my $first_colon_idx = index $uri, q[:];

        if ( $first_colon_idx != -1 ) {
            my $first_slash_idx = index $uri, q[/];

            if ( $first_colon_idx < $first_slash_idx ) {
                $args{scheme} = lc substr $uri, 0, $first_colon_idx, q[];

                substr $uri, 0, 1, q[];
            }
        }
    }

    # authority
    {
        my $authority = q[];

        if ( index( $uri, q[//] ) == 0 ) {
            $args{_has_authority} = 1;

            substr $uri, 0, 2, q[];
        }
        elsif ($with_authority) {
            $args{_has_authority} = 1;
        }

        if ( $args{_has_authority} && $uri =~ s[\A([^/?#]+)][]smo ) {
            $authority = $1;

            my $userinfo_idx = rindex $authority, q[@];

            if ( $userinfo_idx != -1 ) {
                $args{userinfo} = substr $authority, 0, $userinfo_idx, q[];

                substr $authority, 0, 1, q[];

                $args{userinfo} =~ s/([$ESCAPE_RE])/$ESC_CHARS->{$1}/smgo;
            }

            my $port_idx = index $authority, q[:];

            if ( $port_idx != -1 ) {
                $args{host} = substr $authority, 0, $port_idx, q[];

                substr $authority, 0, 1, q[];

                $args{port} = $authority;

                $args{port} =~ s/([$ESCAPE_RE])/$ESC_CHARS->{$1}/smgo;
            }
            else {
                $args{host} = $authority;
            }

            # encode IDN host
            if ( $args{host} =~ m[[^[:ascii:]]]smo ) {
                utf8::decode( $args{host} );

                $args{host} = URI::_idna::encode( lc $args{host} );

                utf8::downgrade( $args{host} );
            }
            else {
                $args{host} = lc $args{host};
            }
        }
    }

    # escape rest of the uri, escape not-allowed characters
    $uri =~ s/([$ESCAPE_RE])/$ESC_CHARS->{$1}/smgo;

    if ( $uri ne q[] ) {
        my $length = length $uri;

        # fragment
        if ( ( my $fragment_idx = index $uri, q[#] ) != -1 ) {
            $args{fragment} = substr $uri, $fragment_idx, $length, q[];

            substr $args{fragment}, 0, 1, q[];    # remove "#" from fragment
        }

        # query
        if ( ( my $query_idx = index $uri, q[?] ) != -1 ) {
            $args{query} = substr $uri, $query_idx, $length, q[];

            substr $args{query}, 0, 1, q[];       # remove "?" from query
        }

        $args{path} = $uri;
    }

    return \%args;
}

# BUILDERS
sub _build_to_string ($self) {

    # https://tools.ietf.org/html/rfc3986#section-5.3
    my $uri = q[];

    $uri .= $self->{scheme} . q[:] if $self->{scheme} ne q[];

    if ( $self->authority ne q[] ) {
        $uri .= q[//] . $self->authority;

        $uri .= q[/] if substr( $self->{path}, 0, 1 ) ne q[/];
    }
    elsif ( $self->{scheme} eq q[] && $self->{path} =~ m[\A[^/]*:]smo ) {
        $uri .= q[./];
    }

    $uri .= $self->{path};

    $uri .= q[?] . $self->{query} if $self->{query} ne q[];

    $uri .= q[#] . $self->{fragment} if $self->{fragment} ne q[];

    return $uri;
}

# TODO:
#     remove default port
#     uppercase escaped series
#     unescape all allowed symbols
#     sort query params
sub _build_canon ($self) {

    # https://tools.ietf.org/html/rfc3986#section-5.3
    my $uri = q[];

    $uri .= $self->{scheme} . q[:] if $self->{scheme} ne q[];

    if ( $self->authority ne q[] ) {
        $uri .= q[//] . $self->authority;

        $uri .= q[/] if substr( $self->path_canon->to_uri, 0, 1 ) ne q[/];
    }
    elsif ( $self->{scheme} eq q[] && $self->path_canon->to_uri =~ m[\A[^/]*:]smo ) {
        $uri .= q[./];
    }

    $uri .= $self->path_canon->to_uri;

    $uri .= q[?] . $self->{query} if $self->{query};

    $uri .= q[#] . $self->{fragment} if $self->{fragment};

    return $uri;
}

sub _build_authority ($self) {
    my $authority = q[];

    $authority .= $self->{userinfo} . q[@] if $self->{userinfo} ne q[];

    $authority .= $self->{host}->name if $self->{host} ne q[];

    $authority .= q[:] . $self->{port} if $self->{port};

    return $authority;
}

sub _build_userinfo_b64 ($self) {
    return q[] if $self->{userinfo} eq q[];

    return P->data->to_b64_url( URI::Escape::XS::decodeURIComponent( $self->{userinfo} ) );
}

sub _build_username ($self) {
    return q[] if $self->{userinfo} eq q[];

    if ( ( my $idx = index $self->{userinfo}, q[:] ) != -1 ) {
        return URI::Escape::XS::decodeURIComponent( substr $self->{userinfo}, 0, $idx );
    }
    else {
        return $self->{userinfo};
    }
}

sub _build_password ($self) {
    return q[] if $self->{userinfo} eq q[];

    if ( ( my $idx = index $self->{userinfo}, q[:] ) != -1 ) {
        return URI::Escape::XS::decodeURIComponent( substr $self->{userinfo}, $idx + 1 );
    }
    else {
        return q[];
    }
}

sub _build_hostport ($self) {
    return $self->host->name . ( $self->port ? q[:] . $self->port : q[] );
}

sub _build_path_canon ($self) {
    my %args = (
        _path  => $self->{path},
        is_abs => 0,
        volume => q[],
    );

    # unescape
    $args{_path} = P->data->from_uri( $args{_path} ) if index( $args{_path}, q[%] ) != -1;

    # convert "\" to "/"
    $args{_path} =~ s[\\+][/]smgo if index( $args{_path}, q[\\] ) != -1;

    # detect if path is absolute
    $args{is_abs} = 1 if substr( $args{_path}, 0, 1 ) eq q[/];

    # parse MSWIN volume
    if ( $MSWIN && $args{_path} =~ s[\A/([[:alpha:]]):/][/]smo ) {
        $args{volume} = lc $1;
    }

    # normalize
    if ( index( $args{_path}, q[.] ) == -1 ) {

        # convert "//" -> "/"
        $args{_path} =~ s[/{2,}][/]smgo;
    }
    else {
        # perform full normalization only if path contains "."
        my @segments;

        my @split = split m[/]smo, $args{_path};

        for my $seg (@split) {
            next if $seg eq q[] || $seg eq q[.];

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

        # add leading "/" for abs path
        unshift @segments, q[] if $args{is_abs};

        # preserve last "/"
        push @segments, q[] if substr( $args{_path}, -1, 1 ) eq q[/] || $split[-1] eq q[.] || $split[-1] eq q[..];

        # concatenate path segments, add leading "/" for abs path
        $args{_path} = join q[/], @segments;
    }

    # add volume
    $args{_path} = $args{volume} . q[:] . $args{_path} if $args{volume};

    return bless \%args, 'Pcore::Util::File::Path';
}

sub _build_scheme_is_valid ($self) {
    return !$self->scheme ? 1 : $self->scheme =~ /\A[[:lower:]][[:lower:][:digit:]+.-]*\z/sm;
}

sub _build_connect_port ($self) {
    return $self->port || $self->default_port;
}

sub _build_connect ($self) {
    my $scheme = $self->scheme eq q[] ? 'tcp' : $self->scheme;

    return [ $self->host->name, $self->connect_port, $scheme, $scheme . q[_] . $self->connect_port ];
}

# UTIL
sub clear_fragment ($self) {
    $self->{fragment} = q[];

    $self->{fragment_utf8} = q[];

    delete $self->{to_string};

    delete $self->{canon};

    return;
}

sub query_params ($self) {
    return P->data->from_uri_query( $self->query );
}

# used to compose url for nginx proxy_pass directive
sub to_nginx ( $self, $scheme = 'http' ) {
    if ( $self->scheme eq 'unix' ) {
        return $scheme . q[://unix:] . $self->path;
    }
    else {
        return $scheme . q[://] . ( $self->host || q[*] ) . ( $self->port ? q[:] . $self->port : q[] );
    }
}

# used to generate addr from Plack::Runner --listen directive
sub to_psgi ($self) {
    if ( $self->scheme eq 'unix' ) {
        return $self->path;
    }
    else {
        return $self->hostport;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 332                  │ Subroutines::ProhibitExcessComplexity - Subroutine "_build_path_canon" with high complexity score (23)         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 101                  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
