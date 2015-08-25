package Pcore::Util::URI;

use Pcore qw[-class];
use AnyEvent::Socket qw[];
use Pcore::Util::File::Path;

use overload    #
  q[""] => sub {
    return $_[0]->to_string;
  },
  q[cmp] => sub {
    return $_[0]->to_string cmp $_[1];
  },
  fallback => undef;

has _scheme    => ( is => 'ro', default  => q[], init_arg => 'scheme' );
has _authority => ( is => 'ro', default  => q[], init_arg => 'authority' );
has _path      => ( is => 'ro', required => 1,   init_arg => 'path' );
has _query     => ( is => 'ro', default  => q[], init_arg => 'query' );
has _fragment  => ( is => 'ro', default  => q[], init_arg => 'fragment' );

has to_string => ( is => 'lazy', clearer => '_clear_to_string', init_arg => undef );

has scheme         => ( is => 'lazy', init_arg => undef );
has authority      => ( is => 'lazy', clearer  => '_clear_authority', init_arg => undef );
has authority_utf8 => ( is => 'lazy', clearer  => '_clear_authority_utf8', init_arg => undef );
has path           => ( is => 'lazy', init_arg => undef );
has query          => ( is => 'rw',   lazy     => 1, init_arg => undef );
has fragment       => ( is => 'rw',   lazy     => 1, init_arg => undef );
has fragment_utf8  => ( is => 'lazy', clearer  => '_clear_fragment_utf8', init_arg => undef );

has scheme_is_valid => ( is => 'lazy', init_arg => undef );

has userinfo => ( is => 'lazy', clearer => '_clear_userinfo', init_arg => undef );
has username => ( is => 'rw',   lazy    => 1,                 init_arg => undef );
has password => ( is => 'rw',   lazy    => 1,                 init_arg => undef );

has host          => ( is => 'rw',   lazy    => 1,                       init_arg => undef );
has port          => ( is => 'rw',   lazy    => 1,                       init_arg => undef );
has hostport      => ( is => 'lazy', clearer => '_clear_host_port',      init_arg => undef );    # in ASCII
has hostport_utf8 => ( is => 'lazy', clearer => '_clear_host_port_utf8', init_arg => undef );

around new => sub ( $orig, $self, $uri, $base = undef ) {
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

    return __PACKAGE__->$orig($args);
};

around username => sub ( $orig, $self, $username = undef ) {
    if ( defined $username ) {
        $self->_clear_userinfo;

        $self->_clear_authority;
        $self->_clear_authority_utf8;

        $self->_clear_to_string;

        utf8::downgrade($username);

        return $self->$orig($username);
    }
    else {
        return $self->$orig;
    }
};

around password => sub ( $orig, $self, $password = undef ) {
    if ( defined $password ) {
        $self->_clear_userinfo;

        $self->_clear_authority;
        $self->_clear_authority_utf8;

        $self->_clear_to_string;

        utf8::downgrade($password);

        return $self->$orig($password);
    }
    else {
        return $self->$orig;
    }
};

around host => sub ( $orig, $self, $host = undef ) {
    if ( defined $host ) {
        $self->_clear_host_port;
        $self->_clear_host_port_utf8;

        $self->_clear_authority;
        $self->_clear_authority_utf8;

        $self->_clear_to_string;

        return $self->$orig( P->host($host) );
    }
    else {
        return $self->$orig;
    }
};

around port => sub ( $orig, $self, $port = undef ) {
    if ( defined $port ) {
        $self->_clear_host_port;
        $self->_clear_host_port_utf8;

        $self->_clear_authority;
        $self->_clear_authority_utf8;

        $self->_clear_to_string;

        utf8::downgrade($port);

        return $self->$orig($port);
    }
    else {
        return $self->$orig;
    }
};

around query => sub ( $orig, $self, $query = undef ) {
    if ( defined $query ) {
        $self->_clear_to_string;

        return $self->$orig( P->data->to_uri( P->data->from_uri_query($query) ) );
    }
    else {
        return $self->$orig;
    }
};

around fragment => sub ( $orig, $self, $fragment = undef ) {
    if ( defined $fragment ) {
        $self->_clear_fragment_utf8;

        $self->_clear_to_string;

        $fragment = P->data->to_uri($fragment);

        return $self->$orig($fragment);
    }
    else {
        return $self->$orig;
    }
};

no Pcore;

sub NEW {
    goto &new;
}

sub _parse ( $uri, @ ) {
    my %args = ();

    my $len = length $uri;

    # fragment
    if ( ( my $fragment_idx = index $uri, q[#] ) != -1 ) {
        $args{fragment} = substr $uri, $fragment_idx, $len, q[];

        substr $args{fragment}, 0, 1, q[];    # remove "#" from fragment
    }
    else {
        $args{fragment} = q[];
    }

    # query
    if ( ( my $query_idx = index $uri, q[?] ) != -1 ) {
        $args{query} = substr $uri, $query_idx, $len, q[];

        substr $args{query}, 0, 1, q[];       # remove "?" from query
    }
    else {
        $args{query} = q[];
    }

    my $has_authority;

    my $hierarchical_part;

    # scheme
    if ( ( my $dbl_slash_idx = index $uri, q[//] ) != -1 ) {    # [scheme:]//[authority][/path]
        $hierarchical_part = $uri;

        $has_authority = 1;

        $args{scheme} = lc substr $hierarchical_part, 0, $dbl_slash_idx + 2, q[];

        if ( $dbl_slash_idx > 0 ) {                             # scheme://
            substr $args{scheme}, -3, 3, q[];                   # remove "://" from scheme
        }
        else {                                                  # //
            substr $args{scheme}, -2, 2, q[];                   # remove "//" from scheme
        }
    }
    else {
        $hierarchical_part = $uri;

        if ( ( my $scheme_idx = index $hierarchical_part, q[:] ) != -1 ) {    # [scheme]:[hierarchical_part]
            $args{scheme} = lc substr $hierarchical_part, 0, $scheme_idx + 1, q[];

            substr $args{scheme}, -1, 1, q[];                                 # remove ":" from scheme
        }
        else {
            $args{scheme} = q[];
        }

        # additional authority parsing
        # uri has authority if hierarchical part contains "@" or ":" before first "/"
        if ($hierarchical_part) {
            my $first_slash_idx = index( $hierarchical_part, q[/] );

            $first_slash_idx = length $hierarchical_part if $first_slash_idx == -1;

            my $userinfo_idx = index $hierarchical_part, q[@];

            if ( $userinfo_idx != -1 && $userinfo_idx < $first_slash_idx ) {    # [user:password]@[host_port][/path]
                $has_authority = 1;
            }
            else {
                my $port_idx = index $hierarchical_part, q[:];

                if ( $port_idx != -1 && $port_idx < $first_slash_idx ) {        # [host]:[port][/path]
                    $has_authority = 1;
                }
            }
        }
    }

    # split hierarchical part to authority + path
    if ($has_authority) {
        if ( ( my $slash_idx = index $hierarchical_part, q[/] ) != -1 ) {
            $args{authority} = substr $hierarchical_part, 0, $slash_idx;

            $args{path} = substr $hierarchical_part, $slash_idx;
        }
        else {
            $args{authority} = $hierarchical_part;
        }
    }
    else {
        $args{authority} = q[];

        $args{path} = $hierarchical_part;
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

    $uri .= q[#] . $self->fragment if $self->fragment;

    return $uri;
}

# SCHEME
sub _build_scheme ($self) {
    my $scheme = $self->_scheme;

    utf8::downgrade($scheme) if utf8::is_utf8($scheme);

    return $scheme;
}

sub _build_scheme_is_valid ($self) {
    return !$self->scheme ? 1 : $self->scheme =~ /\A[[:lower:]][[:lower:][:digit:]+.-]*\z/sm;
}

# AUTHORITY
sub _build_authority ($self) {
    return ( $self->userinfo ? $self->userinfo . q[@] : q[] ) . $self->hostport;
}

sub _build_authority_utf8 ($self) {
    return ( $self->userinfo ? $self->userinfo . q[@] : q[] ) . $self->hostport_utf8;
}

# USERINFO
sub _build_userinfo ($self) {
    return $self->username . ( $self->password ne q[] ? q[:] . $self->password : q[] );
}

sub _build_userinfo_b64 ($self) {
    return P->data->to_b64_url( $self->userinfo );
}

sub _build_username ($self) {
    if ( my $authority = $self->_authority ) {

        # remove host_port
        if ( ( my $idx = index $authority, q[@] ) != -1 ) {
            substr $authority, $idx, length $authority, q[];

            utf8::downgrade($authority);

            if ( ( my $idx = index $authority, q[:] ) != -1 ) {
                return substr $authority, 0, $idx;
            }
            else {
                return $authority;
            }
        }
    }

    return q[];
}

sub clear_username ($self) {
    $self->username(q[]);

    return;
}

sub _build_password ($self) {
    if ( my $authority = $self->_authority ) {

        # remove host_port
        if ( ( my $idx = index $authority, q[@] ) != -1 ) {
            substr $authority, $idx, length $authority, q[];

            utf8::downgrade($authority);

            if ( ( my $idx = index $authority, q[:] ) != -1 ) {
                return substr $authority, $idx + 1;
            }
        }
    }

    return q[];
}

sub clear_password ($self) {
    $self->password(q[]);

    return;
}

# HOST
sub _build_host ($self) {
    my $host = $self->_authority;

    if ($host) {

        # remove userinfo
        if ( ( my $idx = index $host, q[@] ) != -1 ) {
            substr $host, 0, $idx + 1, q[];
        }

        if ( my @host_port = AnyEvent::Socket::parse_hostport($host) ) {
            $host = $host_port[0];
        }
        else {
            $host = q[];
        }
    }

    return P->host($host);
}

sub clear_host ($self) {
    $self->host(q[]);

    return;
}

# PORT
sub _build_port ($self) {
    my $port = 0;

    if ( my $authority = $self->_authority ) {

        # remove userinfo
        if ( ( my $idx = index $authority, q[@] ) != -1 ) {
            substr $authority, 0, $idx + 1, q[];
        }

        if ( my @host_port = AnyEvent::Socket::parse_hostport($authority) ) {
            $port = $host_port[1];

            utf8::downgrade($port);
        }
    }

    return $port;
}

sub clear_port ($self) {
    $self->port(0);

    return;
}

# HOSTPORT
sub _build_hostport ($self) {
    return $self->host->name . ( $self->port ? q[:] . $self->port : q[] );
}

sub _build_hostport_utf8 ($self) {
    return $self->host->name_utf8 . ( $self->port ? q[:] . $self->port : q[] );
}

# PATH
sub _build_path ($self) {
    return $self->_path;
}

# QUERY
sub _build_query ($self) {
    return q[] if $self->_query eq q[];

    return P->data->to_uri( P->data->from_uri_query( $self->_query ) );
}

sub query_params ($self) {
    return P->data->from_uri_query( $self->query );
}

sub clear_query ($self) {
    $self->query(q[]);

    return;
}

# FRAGMENT
sub _build_fragment ($self) {
    return q[] if $self->_fragment eq q[];

    return P->data->to_uri( P->data->from_uri( $self->_fragment ) );
}

sub _build_fragment_utf8 ($self) {
    return q[] if $self->fragment eq q[];

    return P->data->from_uri( $self->fragment );
}

sub clear_fragment ($self) {
    $self->fragment(q[]);

    return;
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
        return $self->hostport;
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
## │    3 │ 1                    │ Modules::ProhibitExcessMainComplexity - Main code has high complexity score (34)                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 79                   │ ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 226                  │ Subroutines::ProhibitExcessComplexity - Subroutine "_parse" with high complexity score (26)                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 285                  │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
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
