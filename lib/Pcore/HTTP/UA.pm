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

use AnyEvent::Handle qw[];
use Errno qw[];
use HTTP::Parser::XS qw[HEADERS_AS_ARRAYREF];
use Pcore::HTTP::Message::Headers;
use Pcore::HTTP::Request;
use Pcore::HTTP::CookieJar;
use Pcore::AnyEvent::Proxy;
use Socket;
use IO::Socket::Socks;
use AnyEvent::Socket;
use Scalar::Util qw[blessed];    ## no critic qw(Modules::ProhibitEvilModules)

our $USERAGENT  = "Mozilla/5.0 (compatible; U; P-AnyEvent-UA/$Pcore::VERSION";
our $RECURSE    = 7;
our $TIMEOUT    = 300;
our $PERSISTENT = 1;
our $KEEPALIVE  = 1;

has useragent  => ( is => 'lazy', isa => Str,               default => $USERAGENT );
has recurse    => ( is => 'lazy', isa => PositiveOrZeroInt, default => $RECURSE );
has timeout    => ( is => 'lazy', isa => PositiveOrZeroInt, default => $TIMEOUT );
has persistent => ( is => 'lazy', isa => Bool,              default => $PERSISTENT );
has keepalive  => ( is => 'lazy', isa => Bool,              default => $KEEPALIVE );
has session    => ( is => 'ro',   isa => Str );

has cookie_jar => ( is => 'rwp', isa => Ref );
has proxy => ( is => 'rw' );
has tls_ctx => ( is => 'lazy', isa => Enum [ $Pcore::HTTP::UA::TLS_CTX_LOW, $Pcore::HTTP::UA::TLS_CTX_HIGH ] | HashRef, default => $Pcore::HTTP::UA::TLS_CTX_LOW );

has headers => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::Message::Headers'], default => sub { Pcore::HTTP::Message::Headers->new }, init_arg => undef );

no Pcore;

# on_prepare
# tcp_connect
# handle_params, { max_read_size => 4_096, }

# changing this is evil, default 4, unused cached connection will be automatically closed after this timeout
our $PERSISTENT_TIMEOUT = 4;

# changing this is evil, default 4, max. parallel connections to the same host
our $MAX_PER_HOST = 1000;
our $ACTIVE       = 0;

my %KA_CACHE;    # indexed by uri host currently, points to [$handle...] array
my %CO_SLOT;     # number of open connections, and wait queue, per host
my $QR_NLNL = qr/(?<![^\n])\r?\n/sm;

# socks constants
my $SOCKS_READ_WATCHER  = 1;
my $SOCKS_WRITE_WATCHER = 2;

our %IDEMPOTENT = (
    DELETE  => 1,
    GET     => 1,
    HEAD    => 1,
    OPTIONS => 1,
    PUT     => 1,
    TRACE   => 1,

    ACL                => 1,
    'BASELINE-CONTROL' => 1,
    BIND               => 1,
    CHECKIN            => 1,
    CHECKOUT           => 1,
    COPY               => 1,
    LABEL              => 1,
    LINK               => 1,
    MERGE              => 1,
    MKACTIVITY         => 1,
    MKCALENDAR         => 1,
    MKCOL              => 1,
    MKREDIRECTREF      => 1,
    MKWORKSPACE        => 1,
    MOVE               => 1,
    ORDERPATCH         => 1,
    PROPFIND           => 1,
    PROPPATCH          => 1,
    REBIND             => 1,
    REPORT             => 1,
    SEARCH             => 1,
    UNBIND             => 1,
    UNCHECKOUT         => 1,
    UNLINK             => 1,
    UNLOCK             => 1,
    UPDATE             => 1,
    UPDATEREDIRECTREF  => 1,
    'VERSION-CONTROL'  => 1,
);

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
        res => $res,

        recurse    => $req->recurse    // ( $self_is_obj ? $self->recurse    : $RECURSE ),
        timeout    => $req->timeout    // ( $self_is_obj ? $self->timeout    : $TIMEOUT ),
        persistent => $req->persistent // ( $self_is_obj ? $self->persistent : $PERSISTENT ),
        keepalive  => $req->keepalive  // ( $self_is_obj ? $self->keepalive  : $KEEPALIVE ),
        session    => $req->session    // ( $self_is_obj ? $self->session    : undef ),
        cookie_jar => $req->cookie_jar // ( $self_is_obj ? $self->cookie_jar : undef ),

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

    $args->{headers}->{TE} = 'trailers' unless exists $args->{headers}->{TE};    # 1.1

    delete $args->{headers}->{CONNECTION};

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

    my $url = ref $req->url ? $req->url : P->uri( $req->url, q[http://] );

    # process proxy
    if ( my $proxy = $req->proxy // ( $self_is_obj ? $self->proxy : undef ) ) {
        $args->{proxy} = Pcore::AnyEvent::Proxy->new( Pcore::AnyEvent::Proxy->parse_uri($proxy) ) if ref $proxy ne 'Pcore::AnyEvent::Proxy';
    }

    my $on_finish = sub {

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
    _http_request( $method, $url, $args, $on_finish );

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

sub get_random_ua {
    state $USER_AGENTS = [    #
        'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/600.1.25 (KHTML, like Gecko) Version/8.0 Safari/600.1.25',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/600.1.25 (KHTML, like Gecko) Version/8.0 Safari/600.1.25',
        'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; rv:11.0) like Gecko',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/600.1.17 (KHTML, like Gecko) Version/7.1 Safari/537.85.10',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.3; WOW64; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.65 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 8_1 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12B411 Safari/600.1.4',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.10; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.1; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.65 Safari/537.36',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 7_1_2 like Mac OS X) AppleWebKit/537.51.2 (KHTML, like Gecko) Version/7.0 Mobile/11D257 Safari/9537.53',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 8_1_1 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12B435 Safari/600.1.4',
        'Mozilla/5.0 (Windows NT 6.3; WOW64; Trident/7.0; rv:11.0) like Gecko',
        'Mozilla/5.0 (iPad; CPU OS 8_1 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12B410 Safari/600.1.4',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (Windows NT 5.1; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
        'Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; WOW64; Trident/6.0)',
        'Mozilla/5.0 (iPad; CPU OS 8_1_1 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12B435 Safari/600.1.4',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/600.1.25 (KHTML, like Gecko) QuickLook/5.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/600.1.25 (KHTML, like Gecko) QuickLook/5.0',
        'Mozilla/5.0 (X11; Linux x86_64; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Windows NT 5.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.65 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/534.59.10 (KHTML, like Gecko) Version/5.1.9 Safari/534.59.10',
        'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:32.0) Gecko/20100101 Firefox/32.0',
        'Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0) like Gecko',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/537.78.2 (KHTML, like Gecko) Version/7.0.6 Safari/537.78.2',
        'Mozilla/5.0 (iPad; CPU OS 7_1_2 like Mac OS X) AppleWebKit/537.51.2 (KHTML, like Gecko) Version/7.0 Mobile/11D257 Safari/9537.53',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/537.78.2 (KHTML, like Gecko) Version/6.1.6 Safari/537.78.2',
        'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:31.0) Gecko/20100101 Firefox/31.0',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 8_0_2 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12A405 Safari/600.1.4',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 8_1_1 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12B436 Safari/600.1.4',
        'Mozilla/5.0 (Windows NT 6.2; WOW64; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)',
        'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.104 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.65 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.3; WOW64; Trident/7.0; Touch; rv:11.0) like Gecko',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 7_1_1 like Mac OS X) AppleWebKit/537.51.2 (KHTML, like Gecko) Version/7.0 Mobile/11D201 Safari/9537.53',
        'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.65 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_5) AppleWebKit/600.1.17 (KHTML, like Gecko) Version/6.2 Safari/537.85.10',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.65 Safari/537.36',
        'Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/38.0.2125.111 Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:34.0) Gecko/20100101 Firefox/34.0',
        'Mozilla/5.0 (Windows NT 6.0; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.7; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/37.0.2062.120 Chrome/37.0.2062.120 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.6; rv:33.0) Gecko/20100101 Firefox/33.0',
        'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (iPad; CPU OS 8_0_2 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12A405 Safari/600.1.4',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.10; rv:34.0) Gecko/20100101 Firefox/34.0',
        'Mozilla/5.0 (Windows NT 5.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.120 Safari/537.36',
        'Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 8_0 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12A365 Safari/600.1.4',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_4) AppleWebKit/537.78.2 (KHTML, like Gecko) Version/7.0.6 Safari/537.78.2',
        'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_4) AppleWebKit/537.77.4 (KHTML, like Gecko) Version/7.0.5 Safari/537.77.4',
        'Mozilla/5.0 (Windows NT 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.111 Safari/537.36',
        'Mozilla/5.0 (Windows NT 6.1; rv:31.0) Gecko/20100101 Firefox/31.0',
        'Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.104 Safari/537.36',
    ];

    return $USER_AGENTS->[ rand @{$USER_AGENTS} ];
}

sub _http_request {
    my $method    = shift;
    my $url       = shift;
    my $args      = shift;
    my $on_finish = shift;

    # set final url to the last accessed url
    $args->{res}->set_url($url);

    my $res = $args->{res};

    return _error( undef, $on_finish, $res, 599, 'Too many redirections' ) if $args->{recurse} < 0;

    my $runtime_headers = Pcore::HTTP::Message::Headers->new;

    my $url_port = $url->port || ( $url->scheme eq 'http' ? 80 : 443 );

    my $starttls = $url->scheme eq 'https' ? 1 : 0;

    my $connect;

    if ( !$args->{proxy} ) {
        $connect->{proxy}     = 'direct';
        $connect->{proxy_key} = 'direct';
        $connect->{host}      = $url->host;
        $connect->{port}      = $url_port;
        $connect->{req_path}  = $url->to_http_req;
    }
    else {

        # choose preferred proxy type
        if ( !$starttls ) {
            $connect->{proxy} = $args->{proxy}->is_http ? 'http' : $args->{proxy}->is_https ? 'https' : 'socks';
        }
        else {
            $connect->{proxy} = $args->{proxy}->is_https ? 'https' : $args->{proxy}->is_socks ? 'socks' : 'http';
        }

        $connect->{proxy_key} = $args->{proxy}->host . q[:] . $args->{proxy}->port;

        # configure connection
        if ( $connect->{proxy} eq 'http' ) {    # http proxy
            $connect->{host}     = $args->{proxy}->host;
            $connect->{port}     = $args->{proxy}->port;
            $connect->{req_path} = $url->to_http_req(1);

            $url_port = 80;
            $starttls = 0;

            $runtime_headers->{PROXY_AUTHORIZATION} = q[Basic ] . $args->{proxy}->auth_b64 if !exists $args->{headers}->{PROXY_AUTHORIZATION} && $args->{proxy}->auth;
        }
        elsif ( $connect->{proxy} eq 'https' ) {    # https proxy
            $connect->{host}     = $args->{proxy}->host;
            $connect->{port}     = $args->{proxy}->port;
            $connect->{req_path} = $url->to_http_req;

            $connect->{https_auth} = exists $args->{headers}->{PROXY_AUTHORIZATION} ? q[Proxy-Authorization: ] . delete( $args->{headers}->{PROXY_AUTHORIZATION} )->[0] . $CRLF : $args->{proxy}->auth ? q[Proxy-Authorization: Basic ] . $args->{proxy}->auth_b64 . $CRLF : q[];
        }
        else {                                      # socks proxy
            $connect->{host}     = $url->host;
            $connect->{port}     = $url_port;
            $connect->{req_path} = $url->to_http_req;

            my $chain;

            push $chain->@*,
              { ver   => $args->{proxy}->socks_ver,
                login => $args->{proxy}->username,
                pass  => $args->{proxy}->password,
                host  => $args->{proxy}->host,
                port  => $args->{proxy}->port,
              };

            $args->{tcp_connect} = sub {
                my ( $cv, $watcher, $timer, $sock );

                _socks_prepare_connection( \$cv, \$watcher, \$timer, $sock, $chain, @_ );
            };
        }
    }

    my $idempotent = $IDEMPOTENT{$method};

    # default value for keepalive is true iff the request is for an idempotent method
    my $persistent = exists $args->{persistent} ? !!$args->{persistent} : $idempotent;

    my $keepalive = exists $args->{keepalive} ? !!$args->{keepalive} : !$args->{proxy};

    my $was_persistent;    # true if this is actually a recycled connection

    # the key to use in the keepalive cache
    my $ka_key = join q[-], $starttls, $connect->{proxy}, $connect->{proxy_key}, $url->host . q[:] . $url_port, $args->{sessionid} // q[];

    # define run-time headers
    $runtime_headers->{REFERER} = $url->to_http_req(1) unless exists $args->{headers}->{REFERER};

    $runtime_headers->{HOST} = $url->host unless exists $args->{headers}->{HOST};

    $runtime_headers->{CONNECTION} = ( $persistent ? $keepalive ? 'keep-alive, ' : q[] : 'close, ' ) . 'Te';    # 1.1

    $args->{cookie_jar}->get_cookies( $runtime_headers, $url->host ) if $args->{cookie_jar};

    my %state = ( connect_guard => 1 );

    # connecting
    my $ae_error = 595;

    # handle actual, non-tunneled, request
    my $handle_actual_request = sub {

        # request phase
        $ae_error = 596;

        my $hdl = $state{handle};

        # start TLS
        $hdl->starttls('connect') if $starttls && !exists $hdl->{tls};

        # send request header
        $hdl->push_write( "$method $connect->{req_path} HTTP/1.1" . $CRLF . $runtime_headers->to_string . $args->{headers}->to_string . $CRLF );

        # send request body
        if ( ref $args->{body} eq 'CODE' ) {
            while (1) {
                if ( my $body_part = $args->{body}->() ) {
                    $hdl->push_write( sprintf( '%X', length $body_part->$* ) . $CRLF . $body_part->$* . $CRLF );
                }
                else {
                    $hdl->push_write( q[0] . $CRLF . $CRLF );

                    last;
                }
            }
        }
        elsif ( exists $args->{body} ) {
            $hdl->push_write( ref $args->{body} ? $args->{body}->$* : $args->{body} );
        }

        # return if error occurred during push_write()
        return unless %state;

        # reduce memory usage, save a kitten (c) Mark Lehmann
        undef $runtime_headers;

        # status line and headers
        $state{read_response} = sub {
            return unless %state;

            my $redirect;

            # parse headers
            if ( my $parsed_headers = _parse_headers( $_[1] . $CRLF ) ) {
                my $status = $parsed_headers->[2];

                # 100 Continue handling
                # should not happen as we don't send expect: 100-continue,
                # but we handle it just in case.
                # since we send the request body regardless, if we get an error
                # we are out of-sync, which we currently do NOT handle correctly.
                return $state{handle}->push_read( line => $QR_NLNL, $state{read_response} ) if $status == 100;

                my $headers = Pcore::HTTP::Message::Headers->new->add( $parsed_headers->[4] );

                $args->{cookie_jar}->parse_cookies( $url->host, $headers->get('SET_COOKIE') ) if $args->{cookie_jar} && $headers->{SET_COOKIE};

                # redirect handling
                # relative uri handling forced by microsoft and other shitheads.
                # we give our best and fall back to URI if available.
                $headers->{LOCATION} = P->uri( $headers->{LOCATION}, $url ) if exists $headers->{LOCATION};

                if ( $args->{recurse} && exists $headers->{LOCATION} ) {

                    # industry standard is to redirect POST as GET for
                    # 301, 302 and 303, in contrast to HTTP/1.0 and 1.1.
                    # also, the UA should ask the user for 301 and 307 and POST,
                    # industry standard seems to be to simply follow.
                    # we go with the industry standard. 308 is defined
                    # by rfc7538
                    if ( $status == 301 or $status == 302 or $status == 303 ) {
                        $redirect = 1;

                        # HTTP/1.1 is unclear on how to mutate the method
                        unless ( $method eq 'HEAD' ) {
                            $method = 'GET';

                            # do not resend request body
                            delete $args->{body};
                        }
                    }
                    elsif ( $status == 307 or $status == 308 ) {
                        $redirect = 1;
                    }

                    if ($redirect) {
                        $res = Pcore::HTTP::Response->new;

                        $res->set_is_http_redirect(1);

                        push $args->{res}->redirect, $res;
                    }
                }

                $res->_set_content_length( delete( $headers->{CONTENT_LENGTH} )->[0] ) if exists $headers->{CONTENT_LENGTH};

                # fill response object with HTTP response headers data
                $res->{headers} = $headers;

                $res->set_version( q[1.] . $parsed_headers->[1] );

                $res->set_status($status);

                $res->set_reason( $parsed_headers->[3] );
            }
            else {
                return _error( \%state, $on_finish, $args->{res}, 599, 'Invalid server response' );
            }

            # define finish callback
            my $finish = sub ( $err_status = undef, $err_reason = undef ) {
                if ( $state{handle} ) {

                    # handle keepalive
                    # if HTTPVersion < 1.1 && CONNECTION_HEADER && CONNECTION_HEADER == "keep-alive" -> keep alive
                    # if HTTPVersion == 1.1 && (!CONNECTION_HEADER || CONNECTION_HEADER != "close") -> keep alive
                    # we do not cache persistent connections and destroy the handle in case of error
                    my $connection_header = $res->headers->{CONNECTION} // q[];

                    if ( $persistent && !defined $err_status && ( $res->version < 1.1 ? $connection_header =~ /\bkeep-?alive\b/smi : $connection_header !~ /\bclose\b/smi ) ) {
                        _ka_store( $ka_key, delete $state{handle} );
                    }
                    else {
                        # no keepalive, destroy the handle
                        $state{handle}->destroy;
                    }
                }

                %state = ();

                # set status, reason and finalize request if error was occured during response body processing
                if ( defined $err_status ) {
                    $res->set_status($err_status);

                    $res->set_reason($err_reason);

                    # set main response status and reason in case of errors during http redirect body processing
                    if ($redirect) {
                        $args->{res}->set_status($err_status);

                        $args->{res}->set_reason( 'Error during HTTP redirect processing. ' . $err_reason );
                    }

                    $on_finish->();
                }
                else {

                    # finalize current request
                    # or run new request in caase of redirect
                    if ($redirect) {

                        $args->{recurse}--;

                        # we ignore any errors, as it is very common to receive
                        # Content-Length != 0 but no actual body
                        $state{recurse} = _http_request(
                            $method,
                            $res->headers->{LOCATION},
                            $args,
                            sub {
                                %state = ();

                                $on_finish->();
                            },
                        );
                    }
                    else {
                        $on_finish->();
                    }
                }

                return;
            };

            # body phase
            $ae_error = 597;

            my $chunked = $res->headers->{TRANSFER_ENCODING} && $res->headers->{TRANSFER_ENCODING} =~ /\bchunked\b/smi;    # not quite correct...

            my $len = $chunked ? 0 : $res->content_length;

            # call "on_progress" callback
            # do not called in redirects
            $args->{on_progress}->( $res, $len, 0 ) if !$redirect && $args->{on_progress};

            # call "on_header" callback
            # do not called in redirects
            $finish->( 598, q[Request cancelled by "on_header"] ) if !$redirect && $args->{on_header} && !$args->{on_header}->($res);

            # read body
            my $status = $res->status;

            if ( $status < 200 || $status == 204 || $status == 205 || $status == 304 || $method eq 'HEAD' || ( !$chunked && $len == 0 ) ) {

                # no body
                $finish->();
            }
            else {
                my $on_body;

                my $total_bytes = 0;

                # init res body
                if ($redirect) {

                    # redirects body always readed into memory
                    # "on_progress", "on_body" are ignored
                    my $body = q[];

                    $res->set_body( \$body );

                    $on_body = sub {
                        $body .= $_[0]->$*;

                        return 1;
                    };
                }
                elsif ( $args->{on_body} ) {
                    $on_body = sub {
                        $args->{on_progress}->( $res, $len, $total_bytes ) if $args->{on_progress};

                        return $args->{on_body}->( $res, $_[0] );
                    };
                }
                else {
                    my $body_is_fh;

                    # detect, where to write body, to memory or to fh
                    # TODO if CONTENT_DISPOSITION - attachment, or contains filename - store as temp file
                    if ( !$args->{chunk_size} ) {
                        $body_is_fh = 0;
                    }
                    else {
                        if ($len) {    # known content length
                            if ( $len > $args->{chunk_size} ) {
                                $body_is_fh = 1;
                            }
                            else {
                                $body_is_fh = 0;
                            }
                        }
                        else {         # content length is unknown
                            $body_is_fh = 1;
                        }
                    }

                    if ($body_is_fh) {
                        $res->set_body( P->file->tempfile );

                        $on_body = sub {
                            syswrite $res->body, $_[0]->$* or die;

                            $args->{on_progress}->( $res, $len, $total_bytes ) if $args->{on_progress};

                            return 1;
                        };
                    }
                    else {
                        my $body = q[];

                        $res->set_body( \$body );

                        $on_body = sub {
                            $body .= $_[0]->$*;

                            $args->{on_progress}->( $res, $len, $total_bytes ) if $args->{on_progress};

                            return 1;
                        };
                    }
                }

                if ($chunked) {    # read chunked body
                    $state{read_chunk} = sub {
                        $_[1] =~ /^([\da-fA-F]+)/sm or return $finish->( $ae_error, 'Garbled chunked transfer encoding' );

                        my $chunk_len = hex $1;

                        if ($chunk_len) {
                            $total_bytes += $chunk_len;

                            $_[0]->push_read(
                                chunk => $chunk_len,
                                sub {
                                    return $finish->( 598, q[Request cancelled by "on_body"] ) if !$on_body->( \$_[1] );

                                    $_[0]->push_read(
                                        line => sub {
                                            length $_[1] and return $finish->( $ae_error, 'Garbled chunked transfer encoding' );

                                            $_[0]->push_read( line => $state{read_chunk} );
                                        }
                                    );
                                }
                            );
                        }
                        else {
                            $res->_set_content_length($total_bytes);

                            # read trailing headers
                            $_[0]->push_read(
                                line => $QR_NLNL,
                                sub {
                                    if ( length $_[1] ) {
                                        if ( my $parsed_headers = _parse_headers( 'HTTP/1.1 200 Trailer Headers' . $_[1] . $CRLF ) ) {
                                            $res->headers->add( $parsed_headers->[4] );
                                        }
                                        else {
                                            return $finish->( $ae_error, 'Garbled response trailers' );
                                        }
                                    }

                                    $finish->();
                                }
                            );
                        }
                    };

                    $_[0]->push_read( line => $state{read_chunk} );
                }
                else {
                    if ( defined $len ) {    # read body with known content length
                        $_[0]->on_read(
                            sub {
                                $total_bytes += length $_[0]{rbuf};

                                return $finish->( 598, q[Request cancelled by "on_body"] ) if !$on_body->( \delete $_[0]{rbuf} );

                                $finish->() if $total_bytes >= $len;
                            }
                        );
                    }
                    else {                   # read body with unknown content length
                        $_[0]->on_eof(
                            sub {
                                $finish->();
                            }
                        );

                        $_[0]->on_read(
                            sub {
                                $total_bytes += length $_[0]{rbuf};

                                return $finish->( 598, q[Request cancelled by "on_body"] ) if !$on_body->( \delete $_[0]{rbuf} );
                            }
                        );
                    }
                }
            }

            return;
        };

        # if keepalive is enabled, then the server closing the connection
        # before a response can happen legally - we retry on idempotent methods.
        if ( $was_persistent && $idempotent ) {
            my $old_eof = $hdl->{on_eof};

            $hdl->{on_eof} = sub {
                _destroy_state( \%state );

                %state = ();

                $args->{recurse}--;

                $args->{persistent} = 0;

                $state{recurse} = _http_request(
                    $method, $url, $args,
                    sub {
                        %state = ();

                        $on_finish->(@_);
                    }
                );
            };

            $hdl->on_read(
                sub {
                    return unless %state;

                    # as soon as we receive something, a connection close
                    # once more becomes a hard error
                    $hdl->{on_eof} = $old_eof;

                    $hdl->push_read( line => $QR_NLNL, $state{read_response} );
                }
            );
        }
        else {
            $hdl->push_read( line => $QR_NLNL, $state{read_response} );
        }
    };

    my $prepare_handle = sub {
        my ($hdl) = $state{handle};

        $hdl->on_error(
            sub {
                _error( \%state, $on_finish, $args->{res}, $ae_error, $_[2] );
            }
        );
        $hdl->on_eof(
            sub {
                _error( \%state, $on_finish, $args->{res}, $ae_error, 'Unexpected end-of-file' );
            }
        );

        $hdl->timeout_reset;

        $hdl->timeout( $args->{timeout} );
    };

    # connected to proxy (or origin server)
    # called only when new connection established, not for cached connections
    my $connect_cb = sub {
        my $fh = shift or return _error( \%state, $on_finish, $args->{res}, $ae_error, qq[$!] );

        return unless delete $state{connect_guard};

        # get handle
        $state{handle} = AnyEvent::Handle->new(
            %{ $args->{handle_params} },
            fh       => $fh,
            peername => $url->host,
            tls_ctx  => $args->{tls_ctx}
        );

        $prepare_handle->();

        # now handle proxy-CONNECT method
        if ( $connect->{proxy} eq 'https' ) {
            $state{handle}->push_write( q[CONNECT ] . $url->host . q[:] . $url_port . q[ HTTP/1.0] . $CRLF . $connect->{https_auth} . $CRLF );

            $state{handle}->push_read(
                line => $QR_NLNL,
                sub {
                    # proxy response processing
                    if ( my $parsed_headers = _parse_headers( $_[1] . $CRLF ) ) {
                        if ( $parsed_headers->[2] == 200 ) {
                            $handle_actual_request->();
                        }
                        else {
                            return _error( \%state, $on_finish, $args->{res}, $parsed_headers->[2], $parsed_headers->[3] );
                        }
                    }
                    else {
                        return _error( \%state, $on_finish, $args->{res}, 599, q[Invalid proxy connect response] );
                    }
                }
            );
        }
        else {
            $handle_actual_request->();
        }
    };

    _get_slot(
        $url->host,
        sub {
            $state{slot_guard} = shift;

            return unless $state{connect_guard};

            # try to use an existing keepalive connection, but only if we, ourselves, plan
            # on a keepalive request (in theory, this should be a separate config option).
            if ( $persistent && $KA_CACHE{$ka_key} ) {
                $was_persistent = 1;

                $state{handle} = _ka_fetch($ka_key);

                $state{handle}->destroyed and die q[AnyEvent::HTTP: unexpectedly got a destructed handle (1), please report.];

                $prepare_handle->();

                $state{handle}->destroyed and die q[AnyEvent::HTTP: unexpectedly got a destructed handle (2), please report.];

                $handle_actual_request->();

            }
            else {
                my $tcp_connect = $args->{tcp_connect} || \&AnyEvent::Socket::tcp_connect;

                # establish TCP connection
                $state{connect_guard} = $tcp_connect->( $connect->{host}, $connect->{port}, $connect_cb, $args->{on_prepare} || sub { $args->{timeout} } );
            }
        }
    );

    return defined wantarray && AnyEvent::Util::guard { _destroy_state( \%state ) };
}

# wait queue/slots
sub _slot_schedule {
    my $host = shift;

    $CO_SLOT{$host}[0] //= 0;

    while ( $CO_SLOT{$host}[0] < $MAX_PER_HOST ) {
        if ( my $cb = shift $CO_SLOT{$host}[1]->@* ) {

            # somebody wants that slot
            ++$CO_SLOT{$host}[0];
            ++$ACTIVE;

            $cb->(
                AnyEvent::Util::guard {
                    --$ACTIVE;
                    --$CO_SLOT{$host}[0];
                    _slot_schedule($host);
                }
            );
        }
        else {
            # nobody wants the slot, maybe we can forget about it
            delete $CO_SLOT{$host} unless $CO_SLOT{$host}[0];

            last;
        }
    }

    return;
}

# wait for a free slot on host, call callback
sub _get_slot {
    push $CO_SLOT{ $_[0] }[1]->@*, $_[1];

    _slot_schedule( $_[0] );

    return;
}

# keepalive/persistent connection cache
# fetch a connection from the keepalive cache
sub _ka_fetch {
    my $ka_key = shift;

    my $hdl = pop $KA_CACHE{$ka_key}->@*;    # currently we reuse the MOST RECENTLY USED connection

    delete $KA_CACHE{$ka_key} unless $KA_CACHE{$ka_key}->@*;

    return $hdl;
}

sub _ka_store {
    my ( $ka_key, $hdl ) = @_;

    my $kaa = $KA_CACHE{$ka_key} ||= [];

    my $destroy = sub {
        my @ka = grep { $_ != $hdl } $KA_CACHE{$ka_key}->@*;

        $hdl->destroy;

        @ka ? $KA_CACHE{$ka_key} = \@ka : delete $KA_CACHE{$ka_key};

        return;
    };

    # on error etc., destroy
    $hdl->on_error($destroy);

    $hdl->on_eof($destroy);

    $hdl->on_read($destroy);

    $hdl->timeout($PERSISTENT_TIMEOUT);

    push $kaa->@*, $hdl;

    while ( $kaa->@* > $MAX_PER_HOST ) {
        shift $kaa->@*;
    }

    return;
}

sub _parse_headers {
    my @res = HTTP::Parser::XS::parse_http_response( $_[0], HEADERS_AS_ARRAYREF );

    if ( $res[0] > 0 ) {
        for ( my $i = 0; $i <= $res[4]->$#*; $i += 2 ) {
            $res[4]->[$i] = uc $res[4]->[$i] =~ tr/-/_/r;
        }

        return \@res;
    }

    return;
}

sub _error ( $state, $on_finish, $res, $status, $reason ) {
    _destroy_state($state) if $state;

    $res->set_status($status);

    $res->set_reason($reason);

    $on_finish->();

    return;
}

sub _destroy_state ($state) {
    $state->{handle}->destroy if $state->{handle};

    $state->%* = ();

    return;
}

# SOCKS
sub _socks_prepare_connection {
    my ( $cv, $watcher, $timer, $sock, $chain, $c_host, $c_port, $c_cb, $p_cb ) = @_;

    unless ($sock) {    # first connection in the chain

        # TODO need also support IPv6 when SOCKS host is a domain name, but this is not so easy
        socket $sock, $chain->[0]{host} =~ /^\[.+\]$/sm ? PF_INET6 : PF_INET, SOCK_STREAM, getprotobyname 'tcp' or return $c_cb->();

        my $timeout = $p_cb->($sock);

        $timer->$* = AnyEvent->timer(    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
            after => $timeout,
            cb    => sub {
                undef $watcher->$*;

                undef $cv->$*;

                $! = Errno::ETIMEDOUT;    ## no critic qw(Variables::RequireLocalizedPunctuationVars)

                $c_cb->();
            }
        );

        for ( $chain->@* ) {
            $_->{host} =~ s/^\[//sm and $_->{host} =~ s/\]$//sm;
        }
    }

    $cv->$* = AE::cv {                    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        _socks_connect( $cv, $watcher, $timer, $sock, $chain, $c_host, $c_port, $c_cb );
    };

    $cv->$*->begin;

    $cv->$*->begin;

    inet_aton(
        $chain->[0]{host},
        sub {
            $chain->[0]{host} = format_address(shift);

            $cv->$*->end if $cv->$*;
        }
    );

    if ( ( $chain->[0]{ver} == 5 && $IO::Socket::Socks::SOCKS5_RESOLVE == 0 ) || ( $chain->[0]{ver} eq '4' && $IO::Socket::Socks::SOCKS4_RESOLVE == 0 ) ) {

        # 4a = 4
        # resolving on the client side enabled
        my $host = $chain->@* > 1 ? \$chain->[1]{host} : \$c_host;

        $cv->$*->begin;

        inet_aton(
            $host->$*,
            sub {
                $host->$* = format_address(shift);    ## no critic qw(Variables::RequireLocalizedPunctuationVars)

                $cv->$*->end if $cv->$*;
            }
        );
    }

    $cv->$*->end;

    return $sock;
}

sub _socks_connect {
    my ( $cv, $watcher, $timer, $sock, $chain, $c_host, $c_port, $c_cb ) = @_;

    my $link = shift $chain->@*;

    my @specopts;

    if ( $link->{ver} eq '4a' ) {
        $link->{ver} = 4;

        push @specopts, SocksResolve => 1;
    }

    if ( defined $link->{login} ) {
        push @specopts, Username => $link->{login};

        if ( $link->{ver} == 5 ) {
            push @specopts, Password => $link->{pass}, AuthType => 'userpass';
        }
    }

    my ( $host, $port ) = $chain->@* ? ( $chain->[0]{host}, $chain->[0]{port} ) : ( $c_host, $c_port );

    if ( ref($sock) eq 'GLOB' ) {

        # not connected socket
        $sock = IO::Socket::Socks->new_from_socket(
            $sock,
            Blocking     => 0,
            ProxyAddr    => $link->{host},
            ProxyPort    => $link->{port},
            SocksVersion => $link->{ver},
            ConnectAddr  => $host,
            ConnectPort  => $port,
            @specopts
        ) or return $c_cb->();
    }
    else {
        $sock->command(
            SocksVersion => $link->{ver},
            ConnectAddr  => $host,
            ConnectPort  => $port,
            @specopts
        ) or return $c_cb->();
    }

    my ( $poll, $w_type ) = $SOCKS_ERROR == SOCKS_WANT_READ ? ( 'r', $SOCKS_READ_WATCHER ) : ( 'w', $SOCKS_WRITE_WATCHER );

    $watcher->$* = AnyEvent->io(    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        fh   => $sock,
        poll => $poll,
        cb   => sub { _socks_handshake( $cv, $watcher, $w_type, $timer, $sock, $chain, $c_host, $c_port, $c_cb ) }
    );

    return;
}

sub _socks_handshake {
    my ( $cv, $watcher, $w_type, $timer, $sock, $chain, $c_host, $c_port, $c_cb ) = @_;

    if ( $sock->ready ) {
        undef $watcher->$*;

        if ( $chain->@* ) {
            return _socks_prepare_connection( $cv, $watcher, $timer, $sock, $chain, $c_host, $c_port, $c_cb );
        }

        undef $timer->$*;

        return $c_cb->($sock);
    }

    if ( $SOCKS_ERROR == SOCKS_WANT_WRITE ) {
        if ( $w_type != $SOCKS_WRITE_WATCHER ) {
            undef $watcher->$*;

            $watcher->$* = AnyEvent->io(    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
                fh   => $sock,
                poll => 'w',
                cb   => sub { _socks_handshake( $cv, $watcher, $SOCKS_WRITE_WATCHER, $timer, $sock, $chain, $c_host, $c_port, $c_cb ) }
            );
        }
    }
    elsif ( $SOCKS_ERROR == SOCKS_WANT_READ ) {
        if ( $w_type != $SOCKS_READ_WATCHER ) {
            undef $watcher->$*;

            $watcher->$* = AnyEvent->io(    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
                fh   => $sock,
                poll => 'r',
                cb   => sub { _socks_handshake( $cv, $watcher, $SOCKS_READ_WATCHER, $timer, $sock, $chain, $c_host, $c_port, $c_cb ) }
            );
        }
    }
    else {
        # unknown error
        $@ = "IO::Socket::Socks: $SOCKS_ERROR";    ## no critic qw(Variables::RequireLocalizedPunctuationVars)

        undef $watcher->$*;

        undef $timer->$*;

        $c_cb->();
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitExcessComplexity                                                                          │
## │      │ 123                  │ * Subroutine "request" with high complexity score (42)                                                         │
## │      │ 433                  │ * Subroutine "_http_request" with high complexity score (130)                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 1133, 1154, 1222,    │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## │      │ 1279                 │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 1148                 │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 324                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 1123                 │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
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

=cut
