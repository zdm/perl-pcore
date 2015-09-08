package Pcore::HTTP::Util;

use Pcore;
use Errno qw[];
use HTTP::Parser::XS qw[HEADERS_AS_ARRAYREF];
use Pcore::AnyEvent::Handle qw[];
use Scalar::Util qw[refaddr];    ## no critic qw[Modules::ProhibitEvilModules];

no Pcore;

sub http_request ($args) {

    # set final url to the last accessed url
    $args->{res}->set_url( $args->{url} );

    my $runtime;

    $runtime = {
        res    => $args->{res},
        h      => undef,
        finish => sub ( $error_status = undef, $error_reason = undef ) {
            state $finished = 0;

            return if $finished;

            $finished = 1;

            my $set_error = sub ( $error_status, $error_reason ) {
                $args->{res}->set_status($error_status);

                $args->{res}->set_reason($error_reason) if defined $error_reason;

                if ( refaddr( $args->{res} ) != refaddr( $runtime->{res} ) ) {
                    $runtime->{res}->set_status($error_status);

                    $runtime->{res}->set_reason($error_reason) if defined $error_reason;
                }

                return;
            };

            if ( defined $error_status ) {    # request was finished with connection / HTTP protocol error
                $runtime->{h}->destroy if $runtime->{h};

                $set_error->( $error_status, $error_reason );
            }
            else {                            # request was finished normally
                my $cache_handle;

                if ( $runtime->{cache_id} && ( $runtime->{persistent} || $runtime->{was_persistent} ) ) {
                    if ( $runtime->{res}->version < 1.1 ) {
                        $cache_handle = 1 if exists $runtime->{res}->headers->{CONNECTION} && $runtime->{res}->headers->{CONNECTION} =~ /\bkeep-?alive\b/smi;
                    }
                    else {                    # 1.1
                        $cache_handle = 1 if !exists $runtime->{res}->headers->{CONNECTION} || $runtime->{res}->headers->{CONNECTION} !~ /\bclose\b/smi;
                    }
                }

                $cache_handle ? $runtime->{h}->store( $runtime->{cache_id} ) : $runtime->{h}->destroy;

                # process redirect
                if ( $runtime->{redirect} ) {
                    if ( $args->{recurse} < 1 ) {
                        $set_error->( 599, 'Too many redirections' );
                    }
                    else {
                        $args->{recurse}--;

                        if ( $runtime->{res}->status ~~ [ 301, 302, 303 ] ) {

                            # HTTP/1.1 is unclear on how to mutate the method
                            if ( $args->{method} ne 'HEAD' ) {
                                $args->{method} = 'GET';

                                # do not resend request body in this case
                                delete $args->{body};
                            }
                        }

                        $args->{url} = $runtime->{res}->headers->{LOCATION};

                        # cleanup and recursive call on redirect
                        $runtime->%* = ();
                        undef $runtime;

                        http_request($args);

                        return;
                    }
                }
            }

            my $on_finish = $args->{on_finish};

            # cleanup data structures manually
            $args->%*    = ();
            $runtime->%* = ();
            undef $runtime;

            $on_finish->();

            return;
        },
        headers         => Pcore::HTTP::Message::Headers->new,
        start_tls       => $args->{url}->is_secure,
        persistent      => $args->{persistent},
        was_persistent  => 0,
        cache_id        => undef,
        request_path    => $args->{url}->pathquery,
        on_error_status => undef,
    };

    # defined connect port
    $runtime->{connect_port} = $args->{url}->port || ( $runtime->{start_tls} ? 443 : 80 );

    # define persistent cache key
    $runtime->{cache_id} = $runtime->{start_tls} . q[-] . $args->{url}->hostport;
    $runtime->{cache_id} .= q[-] . $args->{proxy}->hostport if $args->{proxy};

    # add REFERER header
    $runtime->{headers}->{REFERER} = $args->{url}->pathquery(1) unless exists $args->{headers}->{REFERER};

    # add HOST header
    $runtime->{headers}->{HOST} = $args->{url}->host->name unless exists $args->{headers}->{HOST};

    # mark, that UA support trailer headers during chunked transfer
    $runtime->{headers}->{TE} = 'trailers' unless exists $args->{headers}->{TE};

    # add COOKIE headers
    $args->{cookie_jar}->get_cookies( $runtime->{headers}, $args->{url}->host->name ) if $args->{cookie_jar};

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

            $h->timeout( $args->{timeout} );

            # _write_request does not contain async. code
            _write_request( $args, $runtime );

            # return if error occurred during send request
            return if !$runtime;

            _read_headers(
                $args, $runtime,
                sub {

                    # return if error occurred during read response headers
                    return if !$runtime;

                    # start "read body" phase
                    $runtime->{on_error_status} = 597;

                    _read_body( $args, $runtime, $runtime->{finish} );

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
            $args->{handle_params}->%*,
            connect                => [ $args->{url}->host, $runtime->{connect_port} ],
            connect_timeout        => $args->{timeout},
            timeout                => $args->{timeout},
            tls_ctx                => $args->{tls_ctx},
            peername               => $args->{url}->host->name,
            proxy                  => $args->{proxy},
            on_proxy_connect_error => sub ( $h, $message, $is_connect_error ) {
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
    $runtime->{h}->push_write( "$args->{method} $runtime->{request_path} HTTP/1.1" . $CRLF . $runtime->{headers}->to_string . $args->{headers}->to_string . $CRLF );

    # return if error occurred during send request headers
    return if !$runtime;

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
            return if !$runtime;
        }
    }
    elsif ( exists $args->{body} ) {
        $runtime->{h}->push_write( ref $args->{body} ? $args->{body}->$* : $args->{body} );
    }

    return;
}

sub _read_headers ( $args, $runtime, $cb ) {
    $runtime->{h}->push_read(
        http_headers => sub ( $h, @ ) {

            # parse response headers
            my $parsed_headers = _parse_response_headers( $_[1] );

            if ( !$parsed_headers ) {
                $runtime->{finish}->( 599, 'Invalid server response' );
            }
            else {
                # TODO
                die 'HTTP status 100, 101 are not supporteed correctly yet' if $parsed_headers->{status} == 100 or $parsed_headers->{status} == 101;

                my $headers = Pcore::HTTP::Message::Headers->new->add( $parsed_headers->{headers} );

                # parse SET_COOKIE header, add cookies
                $args->{cookie_jar}->parse_cookies( $args->{url}->host, $headers->get('SET_COOKIE') ) if $args->{cookie_jar} && $headers->{SET_COOKIE};

                # handle redirect
                $runtime->{redirect} = 0;

                if ( exists $headers->{LOCATION} ) {

                    # parse LOCATION header, create uri object
                    $headers->{LOCATION} = P->uri( $headers->{LOCATION}, $args->{url} );

                    if ( $parsed_headers->{status} ~~ [ 301, 302, 303, 307, 308 ] ) {
                        $runtime->{redirect} = 1;

                        # create new response object and set it as default response for current request
                        $runtime->{res} = Pcore::HTTP::Response->new;

                        $runtime->{res}->set_is_http_redirect(1);

                        push $args->{res}->redirect->@*, $runtime->{res};
                    }
                }

                $runtime->{res}->_set_content_length( delete( $headers->{CONTENT_LENGTH} )->[0] ) if exists $headers->{CONTENT_LENGTH};

                # fill response object with HTTP response headers data
                $runtime->{res}->{headers} = $headers;

                $runtime->{res}->set_version( q[1.] . $parsed_headers->{minor_version} );

                $runtime->{res}->set_status( $parsed_headers->{status} );

                $runtime->{res}->set_reason( $parsed_headers->{reason} );
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

    $runtime->{content_length} = $chunked ? 0 : $runtime->{res}->content_length;

    # call "on_progress" callback, not called during redirects
    $args->{on_progress}->( $runtime->{res}, $runtime->{content_length}, 0 ) if !$runtime->{redirect} && $args->{on_progress};

    # call "on_header" callback, do not call during redirects
    if ( !$runtime->{redirect} && $args->{on_header} && !$args->{on_header}->( $runtime->{res} ) ) {
        $cb->( 598, q[Request cancelled by "on_header"] );

        return;
    }

    # no body expected for the following conditions
    if ( $runtime->{res}->status < 200 || $runtime->{res}->status == 204 || $runtime->{res}->status == 205 || $runtime->{res}->status == 304 || $args->{method} eq 'HEAD' || ( !$chunked && $runtime->{content_length} == 0 ) ) {
        $cb->();

        return;
    }

    my $on_body;

    $runtime->{total_bytes_readed} = 0;

    # init res body
    if ( $runtime->{redirect} ) {

        # redirects body always readed into memory
        # "on_progress", "on_body" callbacks are ignored (not called)
        my $body = q[];

        $runtime->{res}->set_body( \$body );

        $on_body = sub ($content_ref) {
            $body .= $content_ref->$*;

            return 1;
        };
    }
    elsif ( $args->{on_body} ) {
        $on_body = sub ($content_ref) {
            $args->{on_progress}->( $runtime->{res}, $runtime->{content_length}, $runtime->{total_bytes_readed} ) if $args->{on_progress};

            return $args->{on_body}->( $runtime->{res}, $content_ref );
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
            if ( $runtime->{content_length} ) {    # known content length
                if ( $runtime->{content_length} > $args->{chunk_size} ) {
                    $body_is_fh = 1;
                }
                else {
                    $body_is_fh = 0;
                }
            }
            else {                                 # content length is unknown
                $body_is_fh = 1;
            }
        }

        # init body and create on_body callback
        if ($body_is_fh) {
            $runtime->{res}->set_body( P->file->tempfile );

            $on_body = sub ($content_ref) {
                syswrite $runtime->{res}->body, $content_ref->$* or die;

                $args->{on_progress}->( $runtime->{res}, $runtime->{content_length}, $runtime->{total_bytes_readed} ) if $args->{on_progress};

                return 1;
            };
        }
        else {
            my $body = q[];

            $runtime->{res}->set_body( \$body );

            $on_body = sub ($content_ref) {
                $body .= $content_ref->$*;

                $args->{on_progress}->( $runtime->{res}, $runtime->{content_length}, $runtime->{total_bytes_readed} ) if $args->{on_progress};

                return 1;
            };
        }
    }

    if ($chunked) {    # read chunked body
        _read_body_chunked( $runtime, $on_body, $cb );
    }
    else {
        if ( $runtime->{content_length} ) {    # read body with known content length
            _read_body_length( $runtime, $on_body, $cb );
        }
        else {                                 # read body with unknown content length (until EOF)
            _read_body_eof( $runtime, $on_body, $cb );
        }
    }

    return;
}

sub _read_body_chunked ( $runtime, $on_body, $cb ) {
    state $last_chunk = qr/(?<![^\n])\r?\n/sm;    # read last chunk. positive for "\r\n" or "...\n\r\n"

    my $read_chunk;

    $read_chunk = sub ( $h, @ ) {
        my $chunk_len_ref = \$_[1];

        if ( $chunk_len_ref->$* =~ /\A([[:xdigit:]]+)\z/sm ) {    # valid chunk length
            my $chunk_len = hex $1;

            if ($chunk_len) {                                     # read chunk body
                $h->push_read(
                    chunk => $chunk_len,
                    sub ( $h, @ ) {
                        my $chunk_ref = \$_[1];

                        $runtime->{total_bytes_readed} += $chunk_len;

                        if ( !$on_body->($chunk_ref) ) {          # transfer was cancelled by "on_body" call

                            # set content length to really readed bytes length
                            $runtime->{res}->_set_content_length( $runtime->{total_bytes_readed} );

                            undef $read_chunk;
                            $cb->( 598, q[Request cancelled by "on_body"] );
                        }
                        else {
                            # read trailing chunk $CRLF
                            $h->push_read(
                                line => sub ( $h, @ ) {
                                    if ( length $_[1] ) {         # error, chunk traililg can contain only $CRLF
                                        undef $read_chunk;
                                        $cb->( 597, 'Garbled chunked transfer encoding' );
                                    }
                                    else {
                                        $h->push_read( line => $read_chunk );
                                    }

                                    return;
                                }
                            );
                        }

                        return;
                    }
                );
            }
            else {    # last chunk
                $runtime->{res}->_set_content_length( $runtime->{total_bytes_readed} );

                # read trailing headers
                $h->push_read(
                    line => $last_chunk,
                    sub ( $h, @ ) {
                        if ( length $_[1] ) {
                            if ( my $parsed_headers = _parse_response_headers( 'HTTP/1.1 200 OK' . $CRLF . $_[1] . $CRLF ) ) {
                                $runtime->{res}->headers->add( $parsed_headers->{headers} );
                            }
                            else {
                                undef $read_chunk;
                                $cb->( 597, 'Garbled chunked transfer encoding (invalid trailing headers)' );

                                return;
                            }
                        }

                        undef $read_chunk;
                        $cb->();

                        return;
                    }
                );
            }
        }
        else {    # invalid chunk length
            undef $read_chunk;
            $cb->( 597, 'Garbled chunked transfer encoding' );
        }

        return;
    };

    $runtime->{h}->push_read( line => $read_chunk );

    return;
}

sub _read_body_length ( $runtime, $on_body, $cb ) {
    $runtime->{h}->on_read(
        sub ($h) {
            $runtime->{total_bytes_readed} += length $h->{rbuf};

            if ( !$on_body->( \delete $h->{rbuf} ) ) {

                # remove "on_read" callback
                $h->on_read(undef);

                $cb->( 598, q[Request cancelled by "on_body"] );
            }

            if ( $runtime->{total_bytes_readed} == $runtime->{content_length} ) {

                # remove "on_read" callback
                $h->on_read(undef);

                $cb->();
            }
            elsif ( $runtime->{total_bytes_readed} > $runtime->{content_length} ) {

                # remove "on_read" callback
                $h->on_read(undef);

                $cb->( 598, q[Readed body length is larger than expected] );
            }

            return;
        }
    );

    return;
}

sub _read_body_eof ( $runtime, $on_body, $cb ) {
    $runtime->{h}->on_eof(
        sub ($h) {
            $cb->();

            return;
        }
    );

    $runtime->{h}->on_read(
        sub ($h) {
            $runtime->{total_bytes_readed} += length $h->{rbuf};

            if ( !$on_body->( \delete $h->{rbuf} ) ) {

                # remove "on_read" callback
                $h->on_read(undef);

                # remove "on_eof" callback
                $h->on_eof(undef);

                $cb->( 598, q[Request cancelled by "on_body"] );
            }

            return;
        }
    );

    return;
}

sub _parse_response_headers {
    my $res = {};

    ( $res->{len}, $res->{minor_version}, $res->{status}, $res->{reason}, $res->{headers} ) = HTTP::Parser::XS::parse_http_response( $_[0], HEADERS_AS_ARRAYREF );

    if ( $res->{len} > 0 ) {

        # repack received headers to the standard format
        for ( my $i = 0; $i <= $res->{headers}->$#*; $i += 2 ) {
            $res->{headers}->[$i] = uc $res->{headers}->[$i] =~ tr/-/_/r;
        }

        return $res;
    }
    else {
        return;
    }
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitExcessComplexity                                                                          │
## │      │ 11                   │ * Subroutine "http_request" with high complexity score (32)                                                    │
## │      │ 346                  │ * Subroutine "_read_body" with high complexity score (34)                                                      │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 83, 96, 97, 198      │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 622                  │ ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Util - Pcore::HTTP::UA helper class

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
