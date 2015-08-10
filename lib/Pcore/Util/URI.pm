package Pcore::Util::URI;

use Pcore qw[-class];
use Pcore::Util::URI::Host;
use Pcore::Util::File::Path;

use overload    #
  q[""] => sub {
    return $_[0]->to_string;
  },
  q[cmp] => sub {
    return $_[0]->to_string cmp $_[1];
  },
  fallback => undef;

has to_string => ( is => 'lazy', isa => Str, clearer => '_clear_to_string', init_arg => undef );

has scheme       => ( is => 'ro',  default  => q[] );
has authority    => ( is => 'ro',  default  => q[] );
has path         => ( is => 'ro',  required => 1 );
has query        => ( is => 'rwp', default  => q[] );
has fragment_raw => ( is => 'rwp', default  => q[] );

has scheme_is_valid => ( is => 'lazy', isa => Bool, init_arg => undef );

has userinfo => ( is => 'lazy', init_arg => undef );
has username => ( is => 'lazy', init_arg => undef );
has password => ( is => 'lazy', init_arg => undef );

has host_port     => ( is => 'lazy', init_arg => undef );
has host          => ( is => 'lazy', init_arg => undef );
has port          => ( is => 'lazy', init_arg => undef );
has canon_domain  => ( is => 'lazy', init_arg => undef );    # host without www. prefix
has root_domain   => ( is => 'lazy', init_arg => undef );
has pub_suffix    => ( is => 'lazy', init_arg => undef );
has host_is_valid => ( is => 'lazy', init_arg => undef );

has fragment => ( is => 'lazy', writer => '_set_fragment', init_arg => undef );

no Pcore;

sub NEW {
    my $self = shift;
    my $uri  = shift;
    my $base = shift;

    my $args = _parse($uri);

    # https://tools.ietf.org/html/rfc3986#section-5
    if ( $args->{scheme} eq q[] && defined $base && $base ne q[] ) {
        $base = _parse($base) if !ref $base;

        # https://tools.ietf.org/html/rfc3986#section-5.2.1
        # base uri MUST contain scheme
        return if $base->{scheme} eq q[];

        # https://tools.ietf.org/html/rfc3986#section-5.2.2
        $args->{scheme} = $base->{scheme};

        if ( $args->{authority} eq q[] ) {

            # inherit authority
            $args->{authority} = $base->{authority};

            # uri has no path
            if ( $args->{path} eq q[] ) {

                # inherit base path
                $args->{path} = $base->{path};

                # inherit base query only if has no own query
                $args->{query} = $base->{query} if $args->{query} eq q[];
            }
            else {
                # https://tools.ietf.org/html/rfc3986#section-5.2.3
                # merge with nase path only if uri path is relative
                if ( substr( $args->{path}, 0, 1 ) ne q[/] ) {    # "/" is not first char - path is relative
                    if ( $args->{authority} && $base->{path} eq q[] ) {
                        $args->{path} = q[/] . $args->{path};
                    }
                    else {
                        if ( $base->{path} eq q[/] ) {
                            $args->{path} = q[/] . $args->{path};
                        }
                        else {
                            $args->{path} = P->file->path( $args->{path}, base => $base->{path} );
                        }
                    }
                }
            }
        }
    }

    # create path object, if not already created
    if ( !ref $args->{path} ) {
        if ( $args->{path} eq q[] ) {
            $args->{path} = bless {
                _path  => q[],
                is_abs => 0,
              },
              'Pcore::Util::File::Path';
        }
        elsif ( $args->{path} eq q[/] ) {
            $args->{path} = bless {
                _path  => q[/],
                is_abs => 1,
              },
              'Pcore::Util::File::Path';
        }
        elsif ( $args->{path} !~ m[(?:[.:\\]|//)]sm ) {
            $args->{path} = bless {
                _path  => $args->{path},
                is_abs => substr( $args->{path}, 0, 1 ) eq q[/] ? 1 : 0,
              },
              'Pcore::Util::File::Path';
        }
        else {
            $args->{path} = P->file->path( $args->{path} );
        }
    }

    return __PACKAGE__->new($args);
}

sub _parse ( $uri, @ ) {
    my %args = ();

    my $len = length $uri;

    # fragment
    if ( ( my $fragment_idx = index $uri, q[#] ) != -1 ) {
        $args{fragment_raw} = substr $uri, $fragment_idx, $len, q[];

        substr $args{fragment_raw}, 0, 1, q[];    # remove "#" from fragment
    }
    else {
        $args{fragment_raw} = q[];
    }

    # query
    if ( ( my $query_idx = index $uri, q[?] ) != -1 ) {
        $args{query} = substr $uri, $query_idx, $len, q[];

        substr $args{query}, 0, 1, q[];           # remove "?" from query
    }
    else {
        $args{query} = q[];
    }

    my $has_authority;

    # scheme
    if ( ( my $dbl_slash_idx = index $uri, q[//] ) != -1 ) {    # [scheme:]//[authority][/path]
        $args{hierarchical_part} = $uri;

        $has_authority = 1;

        $args{scheme} = lc substr $args{hierarchical_part}, 0, $dbl_slash_idx + 2, q[];

        if ( $dbl_slash_idx > 0 ) {                             # scheme://
            substr $args{scheme}, -3, 3, q[];                   # remove "://" from scheme
        }
        else {                                                  # //
            substr $args{scheme}, -2, 2, q[];                   # remove "//" from scheme
        }
    }
    else {
        $args{hierarchical_part} = $uri;

        if ( ( my $scheme_idx = index $args{hierarchical_part}, q[:] ) != -1 ) {    # [scheme]:[hierarchical_part]
            $args{scheme} = lc substr $args{hierarchical_part}, 0, $scheme_idx + 1, q[];

            substr $args{scheme}, -1, 1, q[];                                       # remove ":" from scheme
        }
        else {
            $args{scheme} = q[];
        }

        # additional authority parsing
        # uri has authority if hierarchical part contains "@" or ":" before first "/"
        if ( $args{hierarchical_part} ) {
            my $first_slash_idx = index( $args{hierarchical_part}, q[/] );

            $first_slash_idx = length $args{hierarchical_part} if $first_slash_idx == -1;

            my $userinfo_idx = index $args{hierarchical_part}, q[@];

            if ( $userinfo_idx != -1 && $userinfo_idx < $first_slash_idx ) {    # [user:password]@[host_port][/path]
                $has_authority = 1;
            }
            else {
                my $port_idx = index $args{hierarchical_part}, q[:];

                if ( $port_idx != -1 && $port_idx < $first_slash_idx ) {        # [host]:[port][/path]
                    $has_authority = 1;
                }
            }
        }
    }

    # split hierarchical part to authority + path
    if ($has_authority) {
        if ( ( my $slash_idx = index $args{hierarchical_part}, q[/] ) != -1 ) {
            $args{authority} = substr $args{hierarchical_part}, 0, $slash_idx;

            $args{path} = substr $args{hierarchical_part}, $slash_idx;
        }
        else {
            $args{authority} = $args{hierarchical_part};
        }
    }
    else {
        $args{authority} = q[];

        $args{path} = $args{hierarchical_part};
    }

    if ( !defined $args{path} ) {
        $args{path} = q[];
    }
    else {
        # uri decode path if path contains "%"
        P->data->from_uri( $args{path} ) if $args{path} && index( $args{path}, q[%] ) != -1;
    }

    return \%args;
}

sub _build_to_string ($self) {

    # https://tools.ietf.org/html/rfc3986#section-5.3
    my $uri = q[];

    $uri .= $self->scheme . q[:] if $self->scheme;

    $uri .= q[//] . $self->authority if $self->authority;

    if ( $self->path ) {

        # convert path to absolute if uri has authority
        if ( $self->authority && !$self->path->is_abs ) {
            $uri .= q[/];
        }

        $uri .= $self->path->to_uri;
    }

    $uri .= q[?] . $self->query if $self->query;

    $uri .= q[#] . $self->fragment_raw if $self->fragment_raw;

    return $uri;
}

# SCHEME
sub _build_scheme_is_valid ($self) {
    return !$self->scheme ? 1 : $self->scheme =~ /\A[[:lower:]][[:lower:][:digit:]+.-]*\z/sm;
}

# USERINFO
sub _build_userinfo ($self) {
    if ( $self->authority && ( my $idx = index $self->authority, q[@] ) != -1 ) {
        return substr $self->authority, 0, $idx;
    }

    return q[];
}

sub _build_userinfo_b64 ($self) {
    return P->data->to_b64_url( $self->userinfo );
}

sub _build_username ($self) {
    if ( $self->userinfo ) {
        if ( ( my $idx = index $self->userinfo, q[:] ) != -1 ) {
            return substr $self->userinfo, 0, $idx;
        }
        else {
            return $self->userinfo;
        }
    }

    return q[];
}

sub _build_password ($self) {
    if ( $self->userinfo && ( my $idx = index $self->userinfo, q[:] ) != -1 ) {
        return substr $self->userinfo, $idx + 1;
    }

    return q[];
}

# HOST_PORT
sub _build_host_port ($self) {
    if ( $self->authority ) {
        if ( ( my $idx = index $self->authority, q[@] ) != -1 ) {
            return substr( $self->authority, $idx + 1 );
        }
        else {
            return $self->authority;
        }
    }

    return q[];
}

# HOST
sub _build_host ($self) {
    if ( $self->host_port ) {
        if ( ( my $idx = index $self->host_port, q[:] ) != -1 ) {
            return substr $self->host_port, 0, $idx;
        }
        else {
            return $self->host_port;
        }
    }

    return q[];
}

# PORT
sub _build_port ($self) {
    if ( $self->host_port && ( my $idx = index $self->host_port, q[:] ) != -1 ) {
        return substr $self->host_port, $idx + 1;
    }

    return 0;
}

# QUERY
sub query_params ($self) {
    return P->data->from_uri_query( $self->query );
}

sub set_query ( $self, $query ) {
    $self->_clear_to_string;

    $self->_set_query( P->data->to_uri($query) );

    return;
}

# FRAGMENT
sub _build_fragment ($self) {
    my $fragment = $self->fragment_raw;

    P->data->decode_uri($fragment) if $fragment && index( $fragment, q[%] ) != -1;

    return $fragment;
}

sub set_fragment ( $self, $fragment ) {
    $self->_clear_to_string;

    $self->_set_fragment( $fragment ? P->data->to_uri($fragment) : q[] );

    $self->_set_fragment_raw( $fragment ? P->data->to_uri($fragment) : q[] );

    return;
}

# UTIL
sub _build_canon_domain ($self) {
    if ( my $host = $self->host ) {
        substr $host, 0, 4, q[] if index( $host, 'www.' ) == 0;

        return $host;
    }

    return q[];
}

sub _build_root_domain ($self) {
    if ( my $pub_suffix = $self->pub_suffix ) {
        if ( $self->canon_domain =~ /\A.*?([^.]+[.]$pub_suffix)\z/sm ) {
            return $1;
        }
    }

    return q[];
}

sub _build_pub_suffix ($self) {
    state $suffixes = do {
        my $_suffixes;

        my $path = P->res->get_local('effective_tld_names.dat');

        if ( !$path ) {
            P->ua->request(
                'https://publicsuffix.org/list/effective_tld_names.dat',
                chunk_size  => 0,
                on_progress => 0,
                blocking    => 1,
                on_finish   => sub ($res) {
                    $path = P->res->store_local( 'effective_tld_names.dat', $res->body ) if $res->status == 200;

                    return;
                }
            );
        }

        $_suffixes = { map { $_ => 1 } grep { index( $_, q[//] ) == -1 } P->file->read_lines($path)->@* };
    };

    if ( my $host = $self->canon_domain ) {
        return $host if exists $suffixes->{$host};

        my @parts = split /[.]/sm, $host;

        return q[] if @parts == 1;

        while ( shift @parts ) {
            my $subhost = join q[.], @parts;

            return $subhost if exists $suffixes->{$subhost};
        }
    }

    return q[];
}

sub _build_host_is_valid ($self) {
    if ( my $host = $self->host ) {
        return 0 if bytes::length($host) > 255;    # max length is 255 octets

        return 0 if $host =~ /[^[:alnum:]._\-]/sm; # allowed chars

        return 0 if $host !~ /\A[[:alnum:]]/sm;    # first character should be letter or digit

        return 0 if $host !~ /[[:alnum:]]\z/sm;    # last character should be letter or digit

        for ( split /[.]/sm, $host ) {
            return 0 if bytes::length($_) > 63;    # max. label length is 63 octets
        }

        return 1;
    }

    return 0;
}

# TODO
sub punycode ($self) {
    require URI::_idna;

    if ( $self->host && index( $self->host, 'xn--' ) == 0 ) {
        return URI::_idna::decode( $self->host );
    }

    return q[];
}

# UTIL
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
        return $self->host_port;
    }
}

# convert for using in http requests
sub to_http_req ( $self, $with_auth = undef ) {

    # https://tools.ietf.org/html/rfc3986#section-5.3
    my $uri = q[];

    if ($with_auth) {
        $uri .= $self->scheme . q[:] if $self->scheme;

        $uri .= q[//] . $self->authority if $self->authority;
    }

    if ( $self->path ) {
        $uri .= q[/] if !$self->path->is_abs;

        $uri .= $self->path->to_uri;
    }
    else {
        $uri .= q[/];
    }

    $uri .= q[?] . $self->query if $self->query;

    return $uri;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitExcessComplexity                                                                          │
## │      │ 42                   │ * Subroutine "NEW" with high complexity score (22)                                                             │
## │      │ 125                  │ * Subroutine "_parse" with high complexity score (26)                                                          │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 82                   │ ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 182, 298             │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
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

=cut
