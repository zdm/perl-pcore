package Pcore::Util::URI;

use Pcore qw[-class];
use AnyEvent::Socket qw[];

use overload    #
  q[""] => sub {
    return $_[0]->to_string;
  },
  q[cmp] => sub {
    return $_[0]->to_string cmp $_[1];
  },
  fallback => undef;

has _has_authority => ( is => 'rwp', default  => 0,   init_arg => 'has_authority' );
has _scheme        => ( is => 'ro',  default  => q[], init_arg => 'scheme' );
has _authority     => ( is => 'ro',  default  => q[], init_arg => 'authority' );
has _path          => ( is => 'ro',  required => q[], init_arg => 'path' );
has _query         => ( is => 'ro',  default  => q[], init_arg => 'query' );
has _fragment      => ( is => 'ro',  default  => q[], init_arg => 'fragment' );

has to_string => ( is => 'lazy', clearer => '_clear_to_string', init_arg => undef );

has scheme         => ( is => 'lazy', init_arg => undef );
has authority      => ( is => 'lazy', clearer  => '_clear_authority', init_arg => undef );
has authority_utf8 => ( is => 'lazy', clearer  => '_clear_authority_utf8', init_arg => undef );
has path           => ( is => 'rw',   lazy     => 1, init_arg => undef );
has query          => ( is => 'rw',   lazy     => 1, init_arg => undef );
has fragment       => ( is => 'rw',   lazy     => 1, init_arg => undef );
has fragment_utf8  => ( is => 'lazy', clearer  => '_clear_fragment_utf8', init_arg => undef );

has scheme_is_valid => ( is => 'lazy', init_arg => undef );

has userinfo      => ( is => 'lazy', clearer => '_clear_userinfo',      init_arg => undef );
has username      => ( is => 'rw',   lazy    => 1,                      init_arg => undef );
has username_utf8 => ( is => 'lazy', clearer => '_clear_username_utf8', init_arg => undef );
has password      => ( is => 'rw',   lazy    => 1,                      init_arg => undef );
has password_utf8 => ( is => 'lazy', clearer => '_clear_password_utf8', init_arg => undef );

has host          => ( is => 'rw',   lazy    => 1,                       init_arg => undef );
has port          => ( is => 'rw',   lazy    => 1,                       init_arg => undef );
has hostport      => ( is => 'lazy', clearer => '_clear_host_port',      init_arg => undef );    # in ASCII
has hostport_utf8 => ( is => 'lazy', clearer => '_clear_host_port_utf8', init_arg => undef );

around new => sub ( $orig, $self, $uri, $base = undef ) {
    my $args = _parse($uri);

    # https://tools.ietf.org/html/rfc3986#section-5
    # if URI has no scheme and base URI is specified - merge with base URI
    if ( $args->{scheme} eq q[] && defined $base ) {

        # parse base URI
        if ( !ref $base ) {
            $base = _parse($base);
        }
        else {
            $base = {
                scheme    => $base->_scheme,
                authority => $base->_authority,
                path      => $base->_path,
                query     => $base->_query,
                fragment  => $base->_fragment,
            };
        }

        # https://tools.ietf.org/html/rfc3986#section-5.2.1
        # base URI MUST contain scheme
        return if $base->{scheme} eq q[];

        # https://tools.ietf.org/html/rfc3986#section-5.2.2
        # inherit scheme from base URI
        $args->{scheme} = $base->{scheme};

        # inherit from the base URI only if has no own authority
        if ( !$args->{has_authority} ) {

            # inherit authority
            $args->{authority} = $base->{authority};

            if ( $args->{path} eq q[] ) {
                $args->{path} = $base->{path};

                $args->{query} = $base->{query} if !$args->{query};
            }
            else {
                # path is relative, or no path
                if ( substr( $args->{path}, 0, 1 ) ne q[/] ) {
                    if ( $base->{path} ) {
                        my $slash_rindex = rindex $base->{path}, q[/];

                        # remove filename from base path
                        $base->{path} = substr( $base->{path}, 0, $slash_rindex ) . q[/] if $slash_rindex >= 0;

                        $args->{path} = $base->{path} . q[/] . $args->{path};
                    }
                }
            }
        }
    }

    return __PACKAGE__->$orig($args);
};

around username => sub ( $orig, $self, $username = undef ) {
    if ( defined $username ) {
        $self->_clear_username_utf8;

        $self->_clear_userinfo;

        $self->_clear_authority;
        $self->_clear_authority_utf8;

        $self->_clear_to_string;

        $username = P->data->to_uri($username);

        return $self->$orig($username);
    }
    else {
        return $self->$orig;
    }
};

around password => sub ( $orig, $self, $password = undef ) {
    if ( defined $password ) {
        $self->_clear_password_utf8;

        $self->_clear_userinfo;

        $self->_clear_authority;
        $self->_clear_authority_utf8;

        $self->_clear_to_string;

        $password = P->data->to_uri($password);

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

around path => sub ( $orig, $self, $path = undef ) {
    if ( defined $path ) {
        $self->_clear_to_string;

        return $self->$orig( P->file->path($path) );
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
    my %args = (
        has_authority => 0,
        scheme        => q[],
        authority     => q[],
        path          => q[],
        query         => q[],
        fragment      => q[],
    );

    # fragment
    if ( ( my $fragment_idx = index $uri, q[#] ) != -1 ) {
        $args{fragment} = substr $uri, $fragment_idx, length $uri, q[];

        substr $args{fragment}, 0, 1, q[];    # remove "#" from fragment
    }

    # query
    if ( ( my $query_idx = index $uri, q[?] ) != -1 ) {
        $args{query} = substr $uri, $query_idx, length $uri, q[];

        substr $args{query}, 0, 1, q[];       # remove "?" from query
    }

    # If a URI contains an authority component, then the path component
    # must either be empty or begin with a slash ("/") character.  If a URI
    # does not contain an authority component, then the path cannot begin
    # with two slash characters ("//").  In addition, a URI reference
    # (Section 4.1) may be a relative-path reference, in which case the
    # first path segment cannot contain a colon (":") character.  The ABNF
    # requires five separate rules to disambiguate these cases, only one of
    # which will match the path substring within a given URI reference.  We
    # use the generic term "path component" to describe the URI substring
    # matched by the parser to one of these rules.

    # The authority component is preceded by a double slash ("//") and is
    # terminated by the next slash ("/"), question mark ("?"), or number
    # sign ("#") character, or by the end of the URI.

    if ( ( my $authority_idx = index $uri, q[//] ) != -1 ) {
        $args{has_authority} = 1;

        if ( ( my $slash_idx = index $uri, q[/], $authority_idx + 2 ) != -1 ) {
            $args{authority} = substr $uri, $authority_idx, $slash_idx - $authority_idx, q[];
        }
        else {
            $args{authority} = substr $uri, $authority_idx, length $uri, q[];
        }

        # remove "//" from authority
        substr $args{authority}, 0, 2, q[];
    }

    $args{path} = $uri;

    # A path segment that contains a colon character (e.g., "this:that")
    # cannot be used as the first segment of a relative-path reference, as
    # it would be mistaken for a scheme name.  Such a segment must be
    # preceded by a dot-segment (e.g., "./this:that") to make a relative-
    # path reference.

    if ( ( my $colon_idx = index $args{path}, q[:] ) != -1 ) {
        my $slash_idx = index $args{path}, q[/];

        if ( $slash_idx == -1 or $colon_idx < $slash_idx ) {
            $args{scheme} = lc substr $args{path}, 0, $colon_idx + 1, q[];

            # remove ":" from scheme
            substr $args{scheme}, -1, 1, q[];
        }
    }

    return \%args;
}

sub _build_to_string ($self) {

    # https://tools.ietf.org/html/rfc3986#section-5.3
    my $uri = q[];

    $uri .= $self->scheme . q[:] if $self->scheme;

    if ( $self->_has_authority or $self->authority ) {
        $uri .= q[//] . $self->authority;

        $uri .= q[/] if $self->path && !$self->path->is_abs;
    }
    elsif ( !$self->scheme && $self->path && !$self->path->is_abs && $self->path =~ m[\A[^/]*:]sm ) {
        $uri .= q[./];
    }

    $uri .= $self->path->to_uri;

    $uri .= q[?] . $self->query if $self->query;

    $uri .= q[#] . $self->fragment if $self->fragment;

    return $uri;
}

# SCHEME
sub _build_scheme ($self) {
    my $scheme = $self->_scheme;

    $scheme = P->data->to_uri($scheme);

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

            if ( ( my $idx = index $authority, q[:] ) != -1 ) {
                return P->data->to_uri( substr $authority, 0, $idx );
            }
            else {
                return P->data->to_uri($authority);
            }
        }
    }

    return q[];
}

sub _build_username_utf8 ($self) {
    return q[] if $self->username eq q[];

    return P->data->from_uri( $self->username );
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

            if ( ( my $idx = index $authority, q[:] ) != -1 ) {
                return P->data->to_uri( substr $authority, $idx + 1 );
            }
        }
    }

    return q[];
}

sub _build_password_utf8 ($self) {
    return q[] if $self->password eq q[];

    return P->data->from_uri( $self->password );
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

        if ( index( $host, q[:] ) != -1 ) {
            if ( my @host_port = AnyEvent::Socket::parse_hostport($host) ) {
                $host = $host_port[0];
            }
            else {
                $host = q[];
            }
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
    return P->file->path( P->data->from_uri( $self->_path ) );
}

sub clear_path ($self) {
    $self->path(q[]);

    return;
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
## │    3 │ 1                    │ Modules::ProhibitExcessMainComplexity - Main code has high complexity score (27)                               │
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
