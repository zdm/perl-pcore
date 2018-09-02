package Pcore::Util::URI;

use Pcore -class, -const;
use Pcore::Util::Net qw[get_free_port];
use Pcore::Util::Scalar qw[is_ref];
use Pcore::Util::Data qw[:URI to_b64];
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
use Pcore::Util::UUID qw[uuid_v4_str];
use Clone qw[];

use overload
  q[""]   => sub { return $_[0]->{to_string} },
  q[bool] => sub { return 1 },
  q[cmp]  => sub { return !$_[2] ? $_[0]->canon cmp $_[1] : $_[1] cmp $_[0]->canon },
  fallback => 1;

# http://tools.ietf.org/html/rfc3986#section-2.2
const our $UNRESERVED          => join '', 0 .. 9, 'a' .. 'z', 'A' .. 'Z', q[-._~];
const our $RESERVED_GEN_DELIMS => q[:/?#[]@];
const our $RESERVED_SUB_DELIMS => q[!$&'()*+,;=];
const our $UNSAFE              => do {
    my $safe = { map { $_ => 1 } split //sm, $UNRESERVED . $RESERVED_GEN_DELIMS . $RESERVED_SUB_DELIMS . '%' };

    join '', grep { !$safe->{$_} } map {chr} 0 .. 255;
};

has scheme    => ( is => 'ro' );    # unescaped, utf8
has authority => ();                # escaped
has path      => ();                # object
has query     => ();                # escaped
has fragment  => ();                # escaped

has userinfo => ();                 # escaped
has username => ();                 # unescaped, utf8
has password => ();                 # unescaped, utf8

has host_port => ();                # escaped
has host      => ();                # object
has port      => ();                # int

has path_query => ();               # escaped

has default_port => ();

has to_string     => ();            # escaped
has _canon        => ();            # escaped
has _userinfo_b64 => ();

around new => sub ( $orig, $self, $uri, %args ) {
    if ( !defined $uri ) {
        return if !$args{listen};

        # for windows use TCP loopback
        if ($MSWIN) {
            $uri = '//127.0.0.1:*';
        }

        # for linux use abstract UDS
        else {
            $uri = "///\x00" . uuid_v4_str;
        }
    }

    my ( $scheme, $authority, $path, $query, $fragment ) = $uri =~ m[\A (?:([^:/?#]*):)? (?://([^/?#]*))? ([^?#]+)? (?:[?]([^#]*))? (?:[#](.*))? \z]smx;

    no warnings qw[uninitialized];

    state $class = {};

    # decode scheme, create object
    if ( $scheme ne '' ) {
        $scheme = from_uri_utf8 $scheme;

        $class->{$scheme} = eval { P->class->load( $scheme, ns => 'Pcore::Util::URI' ) } if !exists $class->{scheme};

        $self = bless {}, ( $class->{$scheme} // $self );

        $self->{scheme} = $scheme;
    }
    else {
        $self = bless {}, $self;

        # https://tools.ietf.org/html/rfc3986#section-5
        # if URI has no scheme and base URI is specified - merge with base URI
        if ( my $base = $args{base} ) {
            $base = P->uri($base) if !is_ref $base;

            # Pre-parse the Base URI: https://tools.ietf.org/html/rfc3986#section-5.2.1
            # base URI MUST contain scheme
            if ( defined $base->{scheme} ) {

                #Transform References:  https://tools.ietf.org/html/rfc3986#section-5.2.2
                # inherit scheme from the base URI
                $self->{scheme} = $base->{scheme};

                # inherit from the base URI only if has no own authority
                if ( !defined $authority ) {

                    # inherit authority
                    $authority = $base->{authority};

                    # if source path is empty (undef or "")
                    if ( $path eq '' ) {
                        $path = $base->{path};

                        $query = $base->{query} if !$query;
                    }

                    # source path is not empty
                    else {

                        # Merge Paths: https://tools.ietf.org/html/rfc3986#section-5.2.3

                        # If the base URI has a defined authority component and an empty path,
                        # then return a string consisting of "/" concatenated with the reference's path
                        if ( defined $base->{authority} ) {
                            $path = P->path( $path, base => !defined $base->{path} || $base->{path} eq '' ? '/' : $base->{path}, from_uri => 1 );
                        }

                        # otherwise, merge base + source paths
                        else {
                            $path = P->path( $path, base => $base->{path}, from_uri => 1 );
                        }
                    }
                }
            }
        }
    }

    # authority is emtpy (undef or "")
    if ( $authority eq '' ) {
        $self->{authority} = $authority;
    }
    else {
        $self->_set_authority($authority);
    }

    # path
    if ( is_ref $path) {
        $self->{path} = $path;
    }
    else {

        # set path to '/' it has authority and path is empty
        $path = '/' if defined $authority && $path eq '';

        $self->{path} = P->path( $path, from_uri => 1 ) if $path ne '';
    }

    # set query, if query is not empty
    $self->_set_query($query) if $query ne '';

    # ser fragment, if fragment is not empty
    $self->_set_fragment($fragment) if $fragment ne '';

    if ( $args{listen} ) {

        # host is defined, resolve port
        if ( defined $self->{host} ) {

            # resolve listen port
            $self->{port} = get_free_port $self->{host} if !$self->{port} || $self->{port} eq '*';
        }

        # host and path are not defined
        elsif ( !$self->{path} || $self->{path} eq '/' ) {

            # for windows use TCP loopback
            if ($MSWIN) {
                $self->{host} = P->host('127.0.0.1');

                $self->{port} = get_free_port $self->{host} if !$self->{port} || $self->{port} eq '*';
            }

            # for linux use abstract UDS
            else {
                $self->{path} = P->path( "/\x00" . uuid_v4_str, from_uri => 1 );
            }
        }
    }

    # build uri
    $self->to_string;

    return $self;
};

sub authority ( $self, $val = undef ) {
    no warnings qw[uninitialized];

    if ( @_ > 1 ) {

        # clear related attributes
        delete $self->@{qw[to_string _canon authority userinfo _userinfo_b64 username password host_port host port]};

        # $val match undef or ''
        if ( $val eq '' ) {
            $self->{authority} = $val;
        }
        else {
            $self->_set_authority($val);
        }

        # rebuild uri
        $self->to_string;
    }

    # build authority
    if ( !exists $self->{authority} ) {
        my $authority;

        $authority .= "$self->{userinfo}@" if defined $self->userinfo;

        $authority .= $self->host_port;

        \$self->{authority} = \$authority;
    }

    return $self->{authority};
}

sub userinfo ( $self, $val = undef ) {
    if ( @_ > 1 ) {

        # clear related attributes
        delete $self->@{qw[to_string _canon authority userinfo _userinfo_b64 username password]};

        $self->_set_userinfo($val) if defined $val;

        # rebuild uri
        $self->to_string;
    }

    # build userinfo
    if ( !exists $self->{userinfo} ) {
        my $userinfo;

        $userinfo .= to_uri_component $self->{username} if defined $self->{username};

        $userinfo .= ':' . to_uri_component $self->{password} if defined $self->{password};

        \$self->{userinfo} = \$userinfo;
    }

    return $self->{userinfo};
}

sub username ( $self, $val = undef ) {
    if ( @_ > 1 ) {

        # clear related attributes
        delete $self->@{qw[to_string _canon authority userinfo _userinfo_b64 username]};

        $self->{username} = from_uri_utf8 $val if defined $val;

        # rebuild uri
        $self->to_string;
    }

    return $self->{username};
}

sub password ( $self, $val = undef ) {
    if ( @_ > 1 ) {

        # clear related attributes
        delete $self->@{qw[to_string _canon authority userinfo _userinfo_b64 password]};

        $self->{password} = from_uri_utf8 $val if defined $val;

        # rebuild uri
        $self->to_string;
    }

    return $self->{password};
}

sub host_port ( $self, $val = undef ) {
    if ( @_ > 1 ) {
        delete $self->@{qw[to_string _canon authority host_port host port]};

        $self->_set_host_port($val) if defined $val;

        # rebuild uri
        $self->to_string;
    }

    # build host_port
    if ( !exists $self->{host_port} ) {
        no warnings qw[uninitialized];

        if ( defined $self->{port} ) {
            $self->{host_port} = "$self->{host}:$self->{port}";
        }
        else {
            $self->{host_port} = $self->{host};
        }
    }

    return $self->{host_port};
}

sub host ( $self, $val = undef ) {
    if ( @_ > 1 ) {

        # clear related attributes
        delete $self->@{qw[to_string _canon authority host_port host]};

        $self->{host} = P->host($val) if defined $val;

        # rebuild uri
        $self->to_string;
    }

    return $self->{host};
}

sub port ( $self, $val = undef ) {
    if ( @_ > 1 ) {
        delete $self->@{qw[to_string _canon authority host_port port]};

        $self->{port} = $val;

        # rebuild uri
        $self->to_string;
    }

    return $self->{port};
}

sub path ( $self, $val = undef ) {
    no warnings qw[uninitialized];

    if ( @_ > 1 ) {

        # clear related attributes
        delete $self->@{qw[to_string _canon path path_query]};

        # $val is defined and not ''
        if ( $val ne '' ) {
            my $path = P->path( $val, from_uri => 1 );

            # only abs path is allowed if uri has authority
            if ( defined $self->authority ) {
                if ( $path->is_abs ) {
                    $self->{path} = $path;
                }
                else {
                    die q[Can't set relative path to uri with authority];
                }
            }

            # any path allowed
            else {
                $self->{path} = $path;
            }
        }

        # rebuild uri
        $self->to_string;
    }

    return $self->{path};
}

sub query ( $self, $val = undef ) {
    if ( @_ > 1 ) {

        # clear related attributes
        delete $self->@{qw[to_string _canon query path_query]};

        no warnings qw[uninitialized];

        $self->_set_query($val) if $val ne '';

        # rebuild uri
        $self->to_string;
    }

    return $self->{query};
}

sub fragment ( $self, $val = undef ) {
    if ( @_ > 1 ) {

        # clear related attributes
        delete $self->@{qw[to_string _canon fragment]};

        no warnings qw[uninitialized];

        $self->_set_fragment($val) if $val ne '';

        # rebuild uri
        $self->to_string;
    }

    return $self->{fragment};
}

# UTIL
sub clone ($self) { return Clone::clone($self) }

sub to_abs ( $self, $base ) {
    return $self->clone if defined $self->{scheme};

    return P->uri( $self, base => $base );
}

sub path_query ($self) {
    no warnings qw[uninitialized];

    if ( !exists $self->{path_query} ) {
        my $path_query = defined $self->{path} ? $self->{path}->to_uri : '/';

        $path_query .= "?$self->{query}" if defined $self->{query};

        $self->{path_query} = $path_query;
    }

    return $self->{path_query};
}

sub scheme_is_valid ($self) {
    return !$self->{scheme} ? 1 : $self->{scheme} =~ /\A[[:lower:]][[:lower:][:digit:]+.-]*\z/sm;
}

sub query_params ($self) {
    return if !defined $self->{query};

    return from_uri_query $self->{query};
}

sub query_params_utf8 ($self) {
    return if !defined $self->{query};

    return from_uri_query_utf8 $self->{query};
}

sub connect ($self) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    if ( defined $self->{host} ) {
        return $self->{host}, $self->{port} || $self->{default_port};
    }
    else {
        return 'unix/', $self->{path}->to_string;
    }
}

sub connect_port ($self) {
    return $self->{port} // $self->{default_port};
}

sub userinfo_b64 ($self) {
    if ( !exists $self->{_userinfo_b64} ) {
        if ( defined $self->userinfo ) {
            $self->{_userinfo_b64} = to_b64 $self->{userinfo}, '';
        }
        else {
            $self->{_userinfo_b64} = '';
        }
    }

    return $self->{_userinfo_b64};
}

# host - default port is 80
# 127.0.0.1 - default port is 80
# 127.0.0.1:999
# unix:/path-to-socket
# TODO
sub to_nginx_upstream_server ($self) {
    if ( defined $self->{host} ) {
        return "$self->{host}" . ( $self->{port} ? ":$self->{port}" : '' );
    }
    else {
        return 'unix:' . $self->{path}->to_string;
    }

    return;
}

# used to compose url for nginx proxy_pass directive
# listen 127.0.0.1:12345
# listen *:12345
# listen 12345 - то же, что и *:12345
# listen localhost:12345
# listen unix:/var/run/nginx.sock
# proxy_pass http://localhost:8000/uri/
# proxy_pass http://unix:/tmp/backend.socket:/uri/
# TODO
sub to_nginx ( $self, $scheme = 'http' ) {
    if ( $self->{scheme} eq 'unix' ) {
        return "$scheme://unix:$self->{path}";
    }
    else {
        return "$scheme://" . ( $self->{host} || '*' ) . ( $self->{port} ? ":$self->{port}" : '' );
    }
}

sub _set_authority ( $self, $val ) {
    my $idx = index $val, '@';

    # has userinfo
    if ( $idx != -1 ) {
        my $userinfo = substr $val, 0, $idx;

        my $host_port = substr $val, $idx + 1;

        $self->_set_userinfo($userinfo) if $userinfo ne '';

        $self->_set_host_port($host_port) if $host_port ne '';
    }

    # no userinfo
    else {
        $self->_set_host_port($val) if $val ne '';
    }

    return;
}

sub _set_userinfo ( $self, $val ) {

    # userinfo can be split to username / password
    if ( index( $val, ':' ) != -1 ) {
        my ( $username, $password ) = split /:/sm, $val, 2;

        $self->{username} = from_uri_utf8 $username;

        $self->{password} = from_uri_utf8 $password;
    }

    # userinfo can't be split, store in decoded format
    else {
        $self->{username} = from_uri_utf8 $val;
    }

    return;
}

sub _set_host_port ( $self, $val ) {
    encode_utf8 $val;

    my ( $host, $port ) = split /:/sm, $val, 2;

    $self->{host} = P->host($host) if $host ne '';

    $self->{port} = $port;

    return;
}

sub _set_query ( $self, $val ) {
    $self->{query} = is_ref $val ? to_uri $val : to_uri_query_frag $val;

    return;
}

sub _set_fragment ( $self, $val ) {
    $self->{fragment} = is_ref $val ? to_uri $val : to_uri_query_frag $val;

    return;
}

sub to_string ($self) {
    if ( !exists $self->{to_string} ) {
        my $to_string;

        $to_string .= to_uri_scheme( $self->{scheme} ) . ':' if defined $self->{scheme};

        $to_string .= "//$self->{authority}" if defined $self->authority;

        $to_string .= $self->{path}->to_uri if defined $self->{path};

        $to_string .= "?$self->{query}" if defined $self->{query};

        $to_string .= "#$self->{fragment}" if defined $self->{fragment};

        $self->{to_string} = $to_string;
    }

    return $self->{to_string};
}

# TODO, sort query params
sub canon ($self) {
    ...;
}

# SERIALIZE
*TO_JSON = *TO_CBOR = sub ($self) {
    return $self->{to_string};
};

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 1                    | Modules::ProhibitExcessMainComplexity - Main code has high complexity score (39)                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 64                   | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 116                  | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 586                  | ControlStructures::ProhibitYadaOperator - yada operator (...) used                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 18, 24, 71, 103,     | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |      | 117, 131, 145, 147,  |                                                                                                                |
## |      | 151, 154, 197, 340,  |                                                                                                                |
## |      | 374, 391, 455, 458,  |                                                                                                                |
## |      | 472, 495, 508, 510,  |                                                                                                                |
## |      | 515, 545             |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 60, 177              | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 20                   | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
