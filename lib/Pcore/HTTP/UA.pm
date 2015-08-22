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
use Errno qw[];
use HTTP::Parser::XS qw[HEADERS_AS_ARRAYREF];
use Pcore::AnyEvent::Handle;
use Pcore::HTTP::Message::Headers;
use Pcore::HTTP::Request;
use Pcore::HTTP::CookieJar;

our $USERAGENT = "Mozilla/5.0 (compatible; U; P-AnyEvent-UA/$Pcore::VERSION";
our $RECURSE   = 7;
our $TIMEOUT   = 300;

# default persistent cache timeout, 0 - disable handle cache, changing this is evil, unused cached connection will be automatically closed after this timeout
our $PERSISTENT = 4;
our $KEEPALIVE  = 1;

has useragent  => ( is => 'lazy', isa => Str,               default => $USERAGENT );
has recurse    => ( is => 'lazy', isa => PositiveOrZeroInt, default => $RECURSE );
has timeout    => ( is => 'lazy', isa => PositiveOrZeroInt, default => $TIMEOUT );
has persistent => ( is => 'lazy', isa => PositiveOrZeroInt, default => $PERSISTENT );
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

my $QR_NLNL = qr/(?<![^\n])\r?\n/sm;

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
        method => $method,
        url    => ref $req->url ? $req->url : P->uri( $req->url, q[http://] ),

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

    # process proxy
    if ( my $proxy = $req->proxy // ( $self_is_obj ? $self->proxy : undef ) ) {
        require Pcore::Proxy;

        $args->{proxy} = ref $proxy ne 'Pcore::Proxy' ? Pcore::Proxy->new( { uri => $proxy } ) : $proxy;
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
    _http_request($args);

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

# 594 - errors during proxy handshake.
# 595 - errors during connection establishment.
# 596 - errors during TLS negotiation, request sending and header processing.
# 597 - errors during body receiving or processing.
# 598 - user aborted request via on_header or on_body.
# 599 - other, usually nonretryable, errors (garbled URL etc.).

sub _http_request ($args) {

    # set final url to the last accessed url
    $args->{res}->set_url( $args->{url} );

    my $runtime;

    $runtime = {
        res      => $args->{res},
        h        => undef,
        finished => 0,
        finish   => sub ( $status = undef, $reason = undef ) {
            if ( !$runtime->{finished} ) {
                $runtime->{finished} = 1;

                if ( $runtime->{h} ) {
                    if ( $runtime->{cache_id} && ( $runtime->{persistent} || $runtime->{was_persistent} ) ) {    # store persistent connection
                        $runtime->{h}->store( $runtime->{cache_id}, $runtime->{persistent} );
                    }
                    else {
                        $runtime->{h}->destroy;                                                                  # destroy handle, if connection is not persistent
                    }
                }

                $args->{res}->set_status($status) if defined $status;

                $args->{res}->set_reason($reason) if defined $reason;

                $args->{on_finish}->();
            }

            return;
        },
        headers      => Pcore::HTTP::Message::Headers->new,
        connect_port => $args->{url}->port || ( $args->{url}->scheme eq 'http' ? 80 : 443 ),
        start_tls => $args->{url}->scheme eq 'https' ? 1 : 0,
        persistent      => $args->{persistent},
        was_persistent  => 0,
        cache_id        => undef,
        request_path    => $args->{url}->to_http_req,
        on_error_status => undef,
    };

    # define persistent cache key
    # TODO
    if ( $runtime->{persistent} ) {

        # $runtime->{headers}->{CONNECTION} = ( $persistent ? $keepalive ? 'keep-alive, ' : q[] : 'close, ' ) . 'Te';    # 1.1
    }

    # add REFERER header
    $runtime->{headers}->{REFERER} = $args->{url}->to_http_req(1) unless exists $args->{headers}->{REFERER};

    # add HOST header
    $runtime->{headers}->{HOST} = $args->{url}->host unless exists $args->{headers}->{HOST};

    # add COOKIE headers
    $args->{cookie_jar}->get_cookies( $runtime->{headers}, $args->{url}->host ) if $args->{cookie_jar};

    # start "connect" phase
    $runtime->{on_error_status} = 595;

    _connect(
        $args, $runtime,
        sub ($h) {

            # store handle in the runtime hash
            $runtime->{h} = $h;

            # start "send request / read response headers" phase
            $runtime->{on_error_status} = 596;

            # prepare handle
            $h->on_error(
                sub ( $h, $fatal, $message ) {
                    $runtime->{finish}->( $runtime->{on_error_status}, $message );

                    return;
                }
            );

            $h->on_eof(
                sub {
                    $runtime->{finish}->( $runtime->{on_error_status}, 'Unexpected end-of-file' );

                    return;
                }
            );

            $h->timeout_reset;

            $h->timeout( $args->{timeout} );

            $h->destroyed and die q[AnyEvent::HTTP: unexpectedly got a destructed handle (2), please report.];

            # _write_request does not contain async. code
            _write_request( $args, $runtime );

            # return if error occurred during send request
            return if $runtime->{finished};

            _read_headers(
                $args, $runtime,
                sub () {

                    # return if error occurred during read response headers
                    return if $runtime->{finished};

                    # start "read body" phase
                    $runtime->{on_error_status} = 597;

                    _read_body(
                        $args, $runtime,
                        sub () {

                            # return if error occurred during read response body
                            return if $runtime->{finished};

                            $runtime->{finish}->( 200, 'OK' );

                            return;
                        }
                    );

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub _connect ( $args, $runtime, $cb ) {
    my $_connect = sub {
        my $handle;

        $handle = Pcore::AnyEvent::Handle->new(
            %{ $args->{handle_params} },
            connect                => [ $args->{url}->host, $runtime->{connect_port} ],
            connect_timeout        => $args->{timeout},
            timeout                => $args->{timeout},
            tls_ctx                => $args->{tls_ctx},
            peername               => $args->{url}->host,
            proxy                  => [ 'socks',            $args->{proxy} ],
            on_proxy_connect_error => sub ( $h, $message ) {
                $runtime->{finish}->( 594, $message );

                return;
            },
            on_connect_error => sub ( $h, $message ) {
                $runtime->{finish}->( $runtime->{on_error_status}, $message );

                return;
            },
            on_error => sub ( $h, $fatal, $message ) {
                $runtime->{finish}->( $runtime->{on_error_status}, $message );

                return;
            },
            on_connect => sub ( $h, $host, $port, $retry ) {
                $cb->($handle);

                return;
            },
        );

        return;
    };

    # get connection handle from cache or create new handle
    if ( $runtime->{persistent} && $runtime->{cache_id} ) {
        if ( my $h = Pcore::AnyEvent::Handle->fetch( $runtime->{cache_id} ) ) {
            $h->destroyed and die q[AnyEvent::HTTP: unexpectedly got a destructed handle (1), please report.];

            $runtime->{was_persistent} = 1;

            $cb->($h);
        }
        else {
            $_connect->();
        }
    }
    else {
        $_connect->();
    }

    return;
}

sub _write_request ( $args, $runtime ) {

    # start TLS, only if TLS is required and TLS is not established yet
    $runtime->{h}->starttls('connect') if $runtime->{starttls} && !exists $runtime->{h}->{tls};

    # send request headers
    # TODO HTTP/1.1 - always??? How to support HTTP/1.0???
    $runtime->{h}->push_write( "$args->{method} $runtime->{request_path} HTTP/1.1" . $CRLF . $runtime->{headers}->to_string . $args->{headers}->to_string . $CRLF );

    # return if error occurred during send request headers
    return if $runtime->{finished};

    # send request body
    if ( ref $args->{body} eq 'CODE' ) {
        while (1) {
            if ( my $body_part = $args->{body}->() ) {

                # push chunk
                $runtime->{h}->push_write( sprintf( '%X', length $body_part->$* ) . $CRLF . $body_part->$* . $CRLF );
            }
            else {

                # last chunk
                $runtime->{h}->push_write( q[0] . $CRLF . $CRLF );

                last;
            }

            # return if error occurred during send request body chunk
            return if $runtime->{finished};
        }
    }
    elsif ( exists $args->{body} ) {
        $runtime->{h}->push_write( ref $args->{body} ? $args->{body}->$* : $args->{body} );
    }

    return;
}

sub _read_headers ( $args, $runtime, $cb ) {
    $runtime->{h}->push_read(
        line => $QR_NLNL,
        sub ( $h, $line, $eol ) {

            # parse response headers
            my ( $headers_len, $minor_version, $status, $reason, $raw_headers ) = HTTP::Parser::XS::parse_http_response( $line . $CRLF, HEADERS_AS_ARRAYREF );

            if ( $headers_len <= 0 ) {
                $runtime->{finish}->( 599, 'Invalid server response' );
            }
            else {
                # TODO
                die 'HTTP status 100, 101 are not supporteed correctly yet' if $status == 100 or $status == 101;

                # repack received headers to the standard format
                for ( my $i = 0; $i <= $raw_headers->$#*; $i += 2 ) {
                    $raw_headers->[$i] = uc $raw_headers->[$i] =~ tr/-/_/r;
                }

                my $headers = Pcore::HTTP::Message::Headers->new->add($raw_headers);

                # parse SET_COOKIE header, add cookies
                $args->{cookie_jar}->parse_cookies( $args->{url}->host, $headers->get('SET_COOKIE') ) if $args->{cookie_jar} && $headers->{SET_COOKIE};

                # handle redirect
                $runtime->{redirect} = 0;

                if ( exists $headers->{LOCATION} ) {

                    # parse LOCATION header, create uri object
                    $headers->{LOCATION} = P->uri( $headers->{LOCATION}, $args->{url} );

                    if ( $status == 301 or $status == 302 or $status == 303 ) {
                        $runtime->{redirect} = 1;

                        # HTTP/1.1 is unclear on how to mutate the method
                        # TODO move to the redirect caall
                        # TODO also move redirect counts to the redirect call
                        if ( $args->{method} ne 'HEAD' ) {
                            $args->{method} = 'GET';

                            # do not resend request body in this case
                            delete $args->{body};
                        }
                    }
                    elsif ( $status == 307 or $status == 308 ) {
                        $runtime->{redirect} = 1;
                    }

                    # create new response object and set it as default response for current request
                    if ( $runtime->{redirect} ) {
                        $runtime->{res} = Pcore::HTTP::Response->new;

                        $runtime->{res}->set_is_http_redirect(1);

                        push $args->{res}->redirect->@*, $runtime->{res};
                    }
                }

                $runtime->{res}->_set_content_length( delete( $headers->{CONTENT_LENGTH} )->[0] ) if exists $headers->{CONTENT_LENGTH};

                # fill response object with HTTP response headers data
                $runtime->{res}->{headers} = $headers;

                $runtime->{res}->set_version( q[1.] . $minor_version );

                $runtime->{res}->set_status($status);

                $runtime->{res}->set_reason($reason);
            }

            $cb->();

            return;
        }
    );

    return;
}

sub _read_body ( $args, $runtime, $cb ) {

    # detect chunked transfer, not quite correct...
    my $chunked = $runtime->{res}->headers->{TRANSFER_ENCODING} && $runtime->{res}->headers->{TRANSFER_ENCODING} =~ /\bchunked\b/smi;

    my $len = $chunked ? 0 : $runtime->{res}->content_length;

    # call "on_progress" callback, not called during redirects
    $args->{on_progress}->( $runtime->{res}, $len, 0 ) if !$runtime->{redirect} && $args->{on_progress};

    my $finish = sub ( $status = undef, $reason = undef ) {
        $runtime->{finish}->( 598, q[Request cancelled by "on_header"] );

        $cb->();

        return;
    };

    # call "on_header" callback, do not call during redirects
    return $finish->( 598, q[Request cancelled by "on_header"] ) if !$runtime->{redirect} && $args->{on_header} && !$args->{on_header}->( $runtime->{res} );

    # no body expected for the following conditions
    return $finish->() if $runtime->{res}->status < 200 || $runtime->{res}->status == 204 || $runtime->{res}->status == 205 || $runtime->{res}->status == 304 || $args->{method} eq 'HEAD' || ( !$chunked && $len == 0 );

    my $on_body;

    my $total_bytes_readed = 0;

    # init res body
    if ( $runtime->{redirect} ) {

        # redirects body always readed into memory
        # "on_progress", "on_body" callbacks are ignored (not called)
        my $body = q[];

        $res->set_body( \$body );

        $on_body = sub {
            $body .= $_[0]->$*;

            return 1;
        };
    }
    elsif ( $args->{on_body} ) {
        $on_body = sub {
            $args->{on_progress}->( $runtime->{res}, $len, $total_bytes_readed ) if $args->{on_progress};

            return $args->{on_body}->( $runtime->{res}, $_[0] );
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
            $runtime->{res}->set_body( P->file->tempfile );

            $on_body = sub {
                syswrite $runtime->{res}->body, $_[0]->$* or die;

                $args->{on_progress}->( $runtime->{res}, $len, $total_bytes_readed ) if $args->{on_progress};

                return 1;
            };
        }
        else {
            my $body = q[];

            $runtime->{res}->set_body( \$body );

            $on_body = sub {
                $body .= $_[0]->$*;

                $args->{on_progress}->( $runtime->{res}, $len, $total_bytes_readed ) if $args->{on_progress};

                return 1;
            };
        }
    }

    # TODO do not cache request if was cancelled by "on_header" or by "on_body", because socket can contain data and can't be reusable for next requests

    if ($chunked) {    # read chunked body
        _read_chunked_body(
            $runtime, $on_body,
            sub {
                return;
            }
        );
    }
    else {
        if ( defined $len ) {    # read body with known content length
            _read_length_body(
                $runtime, $on_body,
                sub {
                    return;
                }
            );
        }
        else {                   # read body with unknown content length (until EOF)
            _read_eof_body(
                $runtime, $on_body,
                sub {
                    return;
                }
            );
        }
    }

    return;
}

sub _read_chunked_body ( $runtime, $on_body, $cb ) {
    my $read_chunk;

    $read_chunk = sub ( $h, $chunk ) {
        $chunk =~ /^([\da-fA-F]+)/sm or return $finish->( 597, 'Garbled chunked transfer encoding' );

        my $chunk_len = hex $1;

        if ($chunk_len) {
            $total_bytes_readed += $chunk_len;

            $h->push_read(
                chunk => $chunk_len,
                sub ( $h, $chunk ) {
                    return $finish->( 598, q[Request cancelled by "on_body"] ) if !$on_body->( \$chunk );

                    # read final chunk $CRLF
                    $h->push_read(
                        line => sub ( $h, $chunk ) {
                            length $_[1] and return $finish->( 597, 'Garbled chunked transfer encoding' );

                            $_[0]->push_read( line => $state{read_chunk} );
                        }
                    );
                }
            );
        }
        else {
            $runtime->{res}->_set_content_length($total_bytes_readed);

            # read trailing headers
            $runtime->{h}->push_read(
                line => $QR_NLNL,
                sub ( $h, $line ) {
                    if ( length $line ) {
                        if ( my $parsed_headers = _parse_headers( 'HTTP/1.1 200 Trailer Headers' . $line . $CRLF ) ) {
                            $runtime->{res}->headers->add( $parsed_headers->[4] );
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

    $runtime->{h}->push_read( line => $read_chunk );

    return;
}

sub _read_length_body ( $runtime, $on_body, $cb ) {
    $_[0]->on_read(
        sub {
            $total_bytes += length $_[0]{rbuf};

            return $finish->( 598, q[Request cancelled by "on_body"] ) if !$on_body->( \delete $_[0]{rbuf} );

            $finish->() if $total_bytes >= $len;
        }
    );

    return;
}

sub _read_eof_body ( $runtime, $on_body, $cb ) {

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
## │      │ 108                  │ * Subroutine "request" with high complexity score (42)                                                         │
## │      │ 740                  │ * Subroutine "_read_body" with high complexity score (34)                                                      │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 312                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 675                  │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
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
