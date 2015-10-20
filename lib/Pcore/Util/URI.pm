package Pcore::Util::URI;

use Pcore qw[-class];

use Pcore qw[-class -const];
use Pcore::Util::URI::Host;
use Pcore::Util::URI::Path;
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
has host     => ( is => 'ro' );    # object
has port     => ( is => 'ro' );    # punycoded, ASCII
has path     => ( is => 'ro' );    # object
has query    => ( is => 'ro' );    # escaped, ASCII
has fragment => ( is => 'ro' );    # escaped, ASCII

# TODO canon uri:
#  - remove default port
#  - uppercase escaped series
#  - unescape all allowed symbols
#  - sort query params

has to_string => ( is => 'lazy', init_arg => undef );

has authority    => ( is => 'lazy', init_arg => undef );    # escaped, ASCII, punycoded host
has userinfo_b64 => ( is => 'lazy', init_arg => undef );    # ASCII
has username     => ( is => 'lazy', init_arg => undef );    # unescaped, ASCII
has password     => ( is => 'lazy', init_arg => undef );    # unescaped, ASCII
has hostport     => ( is => 'lazy', init_arg => undef );    # punycoded, ASCII

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
        $args{base} = $self->new( $args{base} ) if !ref $args{base};

        $scheme = $args{base}->{scheme};
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

    $self->_prepare_uri_args( $uri_args, \%args );

    return bless $uri_args, $self;
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

    $uri = q[//] . $uri if $with_authority && index( $uri, q[//] ) == -1;

    # scheme
    {
        my $first_colon_idx = index $uri, q[:];

        if ( $first_colon_idx != -1 ) {
            my $first_slash_idx = index $uri, q[/];

            if ( $first_slash_idx == -1 || $first_colon_idx < $first_slash_idx ) {
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

    if ( $uri ne q[] ) {
        my $length = length $uri;

        # fragment
        if ( ( my $fragment_idx = index $uri, q[#] ) != -1 ) {
            $args{fragment} = substr $uri, $fragment_idx, $length, q[];

            substr $args{fragment}, 0, 1, q[];    # remove "#" from fragment

            # escape
            $args{fragment} =~ s/([$ESCAPE_RE])/$ESC_CHARS->{$1}/smgo;
        }

        # query
        if ( ( my $query_idx = index $uri, q[?] ) != -1 ) {
            $args{query} = substr $uri, $query_idx, $length, q[];

            substr $args{query}, 0, 1, q[];       # remove "?" from query

            # escape
            $args{query} =~ s/([$ESCAPE_RE])/$ESC_CHARS->{$1}/smgo;
        }

        $args{path} = $uri;
    }

    # uri with authority always has "/" path
    $args{path} = q[/] if $args{_has_authority} && $args{path} eq q[];

    return \%args;
}

sub _prepare_uri_args ( $self, $uri_args, $args ) {

    # https://tools.ietf.org/html/rfc3986#section-5
    # if URI has no scheme and base URI is specified - merge with base URI
    $self->_merge_uri_base( $uri_args, $args->{base} ) if $uri_args->{scheme} eq q[] && $args->{base};

    $uri_args->{host} = bless { name => $uri_args->{host} }, 'Pcore::Util::URI::Host' if !ref $uri_args->{host};

    $uri_args->{path} = Pcore::Util::URI::Path->new( $uri_args->{path}, from_uri => 1 ) if !ref $uri_args->{path};

    delete $uri_args->{_has_authority};

    return;
}

sub _merge_uri_base ( $self, $uri_args, $base ) {

    # parse base URI
    $base = $self->new($base) if !ref $base;

    # https://tools.ietf.org/html/rfc3986#section-5.2.1
    # base URI MUST contain scheme
    if ( $base->{scheme} ne q[] ) {

        # https://tools.ietf.org/html/rfc3986#section-5.2.2
        # inherit scheme from base URI
        $uri_args->{scheme} = $base->{scheme};

        # inherit from the base URI only if has no own authority
        if ( !$uri_args->{_has_authority} ) {

            # inherit authority
            $uri_args->{userinfo} = $base->{userinfo};
            $uri_args->{host}     = $base->{host};
            $uri_args->{port}     = $base->{port};

            if ( $uri_args->{path} eq q[] ) {
                $uri_args->{path} = $base->{path};

                $uri_args->{query} = $base->{query} if !$uri_args->{query};
            }
            else {
                $uri_args->{path} = Pcore::Util::URI::Path->new( $uri_args->{path}, base => $base->{path}, from_uri => 1 );
            }
        }
    }

    return;
}

# BUILDERS
sub _build_to_string ($self) {

    # https://tools.ietf.org/html/rfc3986#section-5.3
    my $uri = q[];

    $uri .= $self->{scheme} . q[:] if $self->{scheme} ne q[];

    if ( $self->authority ne q[] ) {
        $uri .= q[//] . $self->authority;

        $uri .= q[/] if !$self->{path}->is_abs;
    }
    elsif ( $self->{scheme} eq q[] && $self->{path}->to_uri =~ m[\A[^/]*:]smo ) {

        # prepend path with "./" if uri has no scheme, has no authority, path is absolute and first path segment contains ":"
        # pa:th/path -> ./pa:th/path
        $uri .= q[./];
    }

    $uri .= $self->{path}->to_uri;

    $uri .= q[?] . $self->{query} if $self->{query} ne q[];

    $uri .= q[#] . $self->{fragment} if $self->{fragment} ne q[];

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
## │    1 │ 96                   │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
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
