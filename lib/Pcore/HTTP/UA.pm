package Pcore::HTTP::UA;

use Pcore qw[-class];
use Const::Fast;

BEGIN {
    const our $TLS_CTX_LOW  => 1;
    const our $TLS_CTX_HIGH => 2;
    const our $TLS_CTX      => {
        $TLS_CTX_LOW  => { cache => 1, sslv2  => 1 },
        $TLS_CTX_HIGH => { cache => 1, verify => 1, verify_peername => 'https' },
    };
}

use Scalar::Util qw[blessed];    ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::HTTP::Util;
use Pcore::HTTP::Message::Headers;
use Pcore::HTTP::Request;
use Pcore::HTTP::CookieJar;
use Const::Fast qw[const];

our $USERAGENT = "Mozilla/5.0 (compatible; U; P-AnyEvent-UA/$Pcore::VERSION";
our $RECURSE   = 7;
our $TIMEOUT   = 300;

has useragent  => ( is => 'lazy', isa => Str,               default => $USERAGENT );
has recurse    => ( is => 'lazy', isa => PositiveOrZeroInt, default => $RECURSE );
has timeout    => ( is => 'lazy', isa => PositiveOrZeroInt, default => $TIMEOUT );
has persistent => ( is => 'lazy', isa => Bool,              default => 1 );
has session    => ( is => 'ro',   isa => Str );

has cookie_jar => ( is => 'rwp', isa => Ref );
has proxy => ( is => 'rw' );
has tls_ctx => ( is => 'lazy', isa => Enum [ $Pcore::HTTP::UA::TLS_CTX_LOW, $Pcore::HTTP::UA::TLS_CTX_HIGH ] | HashRef, default => $Pcore::HTTP::UA::TLS_CTX_LOW );

has headers => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::Message::Headers'], default => sub { Pcore::HTTP::Message::Headers->new }, init_arg => undef );

no Pcore;

const our $HTTP_METHODS => {
    ACL => {
        idempotent => 1,
        safe       => 0
    },
    'BASELINE-CONTROL' => {
        idempotent => 1,
        safe       => 0
    },
    BIND => {
        idempotent => 1,
        safe       => 0
    },
    CHECKIN => {
        idempotent => 1,
        safe       => 0
    },
    CHECKOUT => {
        idempotent => 1,
        safe       => 0
    },
    CONNECT => {
        idempotent => 0,
        safe       => 0
    },
    COPY => {
        idempotent => 1,
        safe       => 0
    },
    DELETE => {
        idempotent => 1,
        safe       => 0
    },
    GET => {
        idempotent => 1,
        safe       => 1
    },
    HEAD => {
        idempotent => 1,
        safe       => 1
    },
    LABEL => {
        idempotent => 1,
        safe       => 0
    },
    LINK => {
        idempotent => 1,
        safe       => 0
    },
    LOCK => {
        idempotent => 0,
        safe       => 0
    },
    MERGE => {
        idempotent => 1,
        safe       => 0
    },
    MKACTIVITY => {
        idempotent => 1,
        safe       => 0
    },
    MKCALENDAR => {
        idempotent => 1,
        safe       => 0
    },
    MKCOL => {
        idempotent => 1,
        safe       => 0
    },
    MKREDIRECTREF => {
        idempotent => 1,
        safe       => 0
    },
    MKWORKSPACE => {
        idempotent => 1,
        safe       => 0
    },
    MOVE => {
        idempotent => 1,
        safe       => 0
    },
    OPTIONS => {
        idempotent => 1,
        safe       => 1
    },
    ORDERPATCH => {
        idempotent => 1,
        safe       => 0
    },
    PATCH => {
        idempotent => 0,
        safe       => 0
    },
    POST => {
        idempotent => 0,
        safe       => 0
    },
    PRI => {
        idempotent => 1,
        safe       => 1
    },
    PROPFIND => {
        idempotent => 1,
        safe       => 1
    },
    PROPPATCH => {
        idempotent => 1,
        safe       => 0
    },
    PUT => {
        idempotent => 1,
        safe       => 0
    },
    REBIND => {
        idempotent => 1,
        safe       => 0
    },
    REPORT => {
        idempotent => 1,
        safe       => 1
    },
    SEARCH => {
        idempotent => 1,
        safe       => 1
    },
    TRACE => {
        idempotent => 1,
        safe       => 1
    },
    UNBIND => {
        idempotent => 1,
        safe       => 0
    },
    UNCHECKOUT => {
        idempotent => 1,
        safe       => 0
    },
    UNLINK => {
        idempotent => 1,
        safe       => 0
    },
    UNLOCK => {
        idempotent => 1,
        safe       => 0
    },
    UPDATE => {
        idempotent => 1,
        safe       => 0
    },
    UPDATEREDIRECTREF => {
        idempotent => 1,
        safe       => 0
    },
    'VERSION-CONTROL' => {
        idempotent => 1,
        safe       => 0
    }
};

# 594 - errors during proxy handshake.
# 595 - errors during connection establishment.
# 596 - errors during TLS negotiation, request sending and header processing.
# 597 - errors during body receiving or processing.
# 598 - user aborted request via on_header or on_body.
# 599 - other, usually nonretryable, errors (garbled URL etc.).

sub BUILDARGS {
    my $self = shift;
    my $args = shift;

    $args->{cookie_jar} = Pcore::HTTP::CookieJar->new if $args->{cookie_jar} && $args->{cookie_jar} == 1;

    return $args;
}

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->headers->add( $args->{headers} ) if $args->{headers};

    return;
}

sub request ( $self, @ ) {
    my ( $req, $req_args );

    # parse request args
    if ( ref $_[1] eq 'HASH' || ( blessed( $_[1] ) && $_[1]->isa('Pcore::HTTP::Request') ) ) {    # first arg is req object or HashRef
        $req = ref $_[1] eq 'HASH' ? Pcore::HTTP::Request->new( $_[1] ) : $_[1];

        $req_args = ref $_[2] eq 'HASH' ? $_[2] : { @_[ 2 .. $#_ ] };
    }
    else {
        if ( exists $Pcore::HTTP::Request::HTTP_METHODS->{ $_[1] } ) {                            # first arg is method name
            $req = Pcore::HTTP::Request->new( { method => $_[1], url => $_[2], @_[ 3 .. $#_ ] } );
        }
        else {                                                                                    # first arg is url, method = GET
            $req = Pcore::HTTP::Request->new( { method => 'GET', url => $_[1], @_[ 2 .. $#_ ] } );
        }
    }

    my $method = $req_args->{method} || $req->method;

    my $cv = $req->blocking // $req_args->{blocking} // 0;

    # create res object
    my $res = Pcore::HTTP::Response->new;

    my $self_is_obj = ref $self ? 1 : 0;

    # create AnyEvent::HTTP params
    my $args = {
        method => $method,
        url    => ref $req->url ? $req->url : P->uri( $req->url, q[http://] ),

        res => $res,

        recurse    => $req->recurse    // ( $self_is_obj ? $self->recurse    : $RECURSE ),
        timeout    => $req->timeout    // ( $self_is_obj ? $self->timeout    : $TIMEOUT ),
        persistent => $req->persistent // ( $self_is_obj ? $self->persistent : 1 ),
        session    => $req->session    // ( $self_is_obj ? $self->session    : undef ),
        cookie_jar => $req->cookie_jar // ( $self_is_obj ? $self->cookie_jar : undef ),
        proxy      => $req->proxy      // ( $self_is_obj ? $self->proxy      : undef ),

        tls_ctx => $req->tls_ctx // ( $self_is_obj ? $self->tls_ctx : $Pcore::HTTP::UA::TLS_CTX_LOW ),

        chunk_size => $req_args->{chunk_size} // $req->chunk_size,

        headers => $req->headers->clone,
        body    => $req->body,

        on_progress => $req->on_progress,
        on_header   => $req->on_header,
        on_body     => $req->on_body,
    };

    $args->{handle_params} = { max_read_size => 1_048_576 };

    # prepare headers
    $args->{headers}->replace( $self->headers->get_hash ) if $self_is_obj;

    $args->{headers}->replace( $req_args->{headers} ) if $req_args->{headers};

    $args->{headers}->{USER_AGENT} = $self_is_obj ? $self->useragent : $USERAGENT unless exists $args->{headers}->{USER_AGENT};

    # prepate TLS context
    if ( !$args->{tls_ctx} ) {
        $args->{tls_ctx} = $Pcore::HTTP::UA::TLS_CTX->{$Pcore::HTTP::UA::TLS_CTX_LOW};
    }
    elsif ( !ref $args->{tls_ctx} ) {
        $args->{tls_ctx} = $Pcore::HTTP::UA::TLS_CTX->{ $args->{tls_ctx} };
    }

    # prepare body, if req has body and method allow send body
    if ( $req->has_body && $Pcore::HTTP::Request::HTTP_METHODS->{$method} ) {
        $args->{body} = $req->body_to_ae_http;

        if ( ref $args->{body} eq 'CODE' ) {
            delete $args->{headers}->{CONTENT_LENGTH};

            $args->{headers}->{TRANSFER_ENCODING} = 'chunked';
        }
        else {
            $args->{headers}->{CONTENT_LENGTH} = bytes::length( ref $args->{body} eq 'SCALAR' ? $args->{body}->$* : $args->{body} );
        }
    }

    # process proxy
    if ( $args->{proxy} && !ref $args->{proxy} ) {
        require Pcore::Proxy;

        $args->{proxy} = Pcore::Proxy->new( $args->{proxy} );
    }

    $args->{on_finish} = sub {

        # rewind body fh
        $res->body->seek( 0, 0 ) if $res->has_body && P->scalar->is_glob( $res->body );

        # before_finish callback
        $req_args->{before_finish}->($res) if $req_args->{before_finish};

        # on_finish callback
        $req->on_finish->($res) if $req->on_finish;

        $cv->end if $cv;

        return;
    };

    my $blocking;

    if ($cv) {
        if ( !ref $cv ) {
            $cv = AE::cv;

            $blocking = 1;
        }

        $cv->begin;
    }

    # throw request
    Pcore::HTTP::Util::http_request($args);

    $cv->recv if $blocking;

    return;
}

sub get {
    my $self = shift;

    return $self->_redefine_method( 'GET', @_ );
}

sub post {
    my $self = shift;

    return $self->_redefine_method( 'POST', @_ );
}

sub _redefine_method ( $self, $method, @ ) {
    my ( $req, $req_args );

    if ( ref $_[2] eq 'HASH' || ( blessed( $_[2] ) && $_[2]->isa('Pcore::HTTP::Request') ) ) {    # second arg is req object or HashRef
        $req = $_[2];

        $req_args = ref $_[3] eq 'HASH' ? $_[3] : { @_[ 3 .. $#_ ] };
    }
    else {
        if ( exists $Pcore::HTTP::Request::HTTP_METHODS->{ $_[2] } ) {                            # second arg is method name
            $req = { method => $_[2], url => $_[3], @_[ 4 .. $#_ ] };
        }
        else {
            $req = { method => 'GET', url => $_[2], @_[ 3 .. $#_ ] };                             # second arg is url
        }
    }

    $req_args->{method} = $method;

    return $self->request( $req, $req_args );
}

# additional params supported:
# no_cache => 1;
sub mirror ( $self, @ ) {
    my ( $req, $target, $req_args );

    # parse request args
    if ( ref $_[1] eq 'HASH' || ( blessed( $_[1] ) && $_[1]->isa('Pcore::HTTP::Request') ) ) {
        $req = $_[1];

        $target = $_[2];

        $req_args = ref $_[3] eq 'HASH' ? $_[3] : { @_[ 3 .. $#_ ] };
    }
    else {
        if ( exists $Pcore::HTTP::Request::HTTP_METHODS->{ $_[1] } ) {
            $req = { method => $_[1], url => $_[2], @_[ 4 .. $#_ ] };

            $target = $_[3];
        }
        else {
            $req = { method => 'GET', url => $_[1], @_[ 3 .. $#_ ] };

            $target = $_[2];
        }

        $req_args->{no_cache} = delete $req->{no_cache};
    }

    $req_args->{chunk_size} = 1;

    if ( !$req_args->{no_cache} && -f $target ) {
        $req_args->{headers}->{IF_MODIFIED_SINCE} = P->date->from_epoch( [ stat $target ]->[9] )->to_http_date;
    }

    $req_args->{before_finish} = sub ($res) {
        if ( $res->status == 200 ) {
            P->file->move( $res->body->path, $target );

            if ( my $last_modified = $res->headers->{LAST_MODIFIED} ) {
                my $mtime = P->date->parse($last_modified)->at_utc->epoch;

                utime $mtime, $mtime, $target or die;
            }
        }

        return;
    };

    return $self->request( $req, $req_args );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 224                  │ Subroutines::ProhibitExcessComplexity - Subroutine "request" with high complexity score (40)                   │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 424                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::UA

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 persistent = Bool

Store connection in cache. C<FALSE> - do not cache connection. C<TRUE> - cache connection. Connection will not be cached in cases where proxies was used or on HTTP protocol errors.

Default value is C<1>.

=head1 METHODS

=cut
