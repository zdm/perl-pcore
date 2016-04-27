package Pcore::HTTP::Util;

use Pcore -const;
use Errno qw[];
use Pcore::AE::Handle qw[:PERSISTENT :PROXY_TYPE];
use Pcore::Util::Scalar qw[refaddr];
use Compress::Raw::Zlib qw[WANT_GZIP_OR_ZLIB Z_OK Z_STREAM_END];

const our $CONTENT_ENCODING_GZIP     => 1;    # NOTE only gzip is supported now
const our $CONTENT_ENCODING_COMPRESS => 2;
const our $CONTENT_ENCODING_DEFLATE  => 3;
const our $CONTENT_ENCODING_IDENTITY => 4;

# $status => $switch_method_to_GET
const our $REDIRECT => {
    301 => 1,                                 # should ask user to repeat request, in auto mode - repeat as GET
    302 => 1,                                 # resend request as GET
    303 => 1,                                 # always change method to GET, used in POST-GET requeusts chain
    307 => 0,                                 # do not change method
    308 => 0,                                 # do not change method
};

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
                $args->{res}->set_status( $error_status, $error_reason );

                if ( refaddr( $args->{res} ) != refaddr( $runtime->{res} ) ) {
                    $runtime->{res}->set_status( $error_status, $error_reason );
                }

                return;
            };

            if ( defined $error_status ) {    # request was finished with connection / HTTP protocol error
                $runtime->{h}->destroy if $runtime->{h};

                $set_error->( $error_status, $error_reason );
            }
            else {                            # request was finished normally
                my $persistent = $runtime->{h}->{persistent} || $args->{persistent};

                $persistent = 0 if $runtime->{h}->{proxy} && $args->{persistent} == $PERSISTENT_NO_PROXY;

                if ($persistent) {
                    if ( $runtime->{res}->{version} == 1.1 ) {    # HTTP/1.1
                        $persistent = 0 if $runtime->{res}->headers->{CONNECTION} && $runtime->{res}->headers->{CONNECTION} =~ /\bclose\b/smio;
                    }
                    elsif ( $runtime->{res}->{version} == 1.0 ) {    # HTTP/1.0
                        $persistent = 0 if !$runtime->{res}->headers->{CONNECTION} || $runtime->{res}->headers->{CONNECTION} !~ /\bkeep-?alive\b/smio;
                    }
                }

                $persistent ? $runtime->{h}->store : $runtime->{h}->destroy;

                # process redirect
                if ( $runtime->{redirect} ) {
                    if ( $args->{recurse} < 1 ) {
                        $set_error->( 599, 'Too many redirections' );
                    }
                    else {
                        $args->{recurse}--;

                        # redirect type may require to switch request method during redirect
                        if ( $REDIRECT->{ $runtime->{res}->status } ) {

                            # change method to GET if original method was not "GET" or "HEAD"
                            $args->{method} = 'GET' if $args->{method} ne 'HEAD';

                            # do not resend request body
                            delete $args->{body};
                        }

                        $args->{url} = $runtime->{res}->headers->{LOCATION};

                        # set HOST header
                        $args->{headers}->{HOST} = $args->{url}->host->name;

                        # replace COOKIE headers
                        if ( $args->{cookie_jar} && ( my $cookies = $args->{cookie_jar}->get_cookies( $args->{url} ) ) ) {
                            $args->{headers}->{COOKIE} = join q[; ], $cookies->@*;
                        }
                        else {
                            delete $args->{headers}->{COOKIE};
                        }

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
            $args->%* = ();

            $runtime->%* = ();

            undef $runtime;

            $on_finish->();

            return;
        },
        on_error_status => undef,
    };

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
    Pcore::AE::Handle->new(
        $args->{handle_params}->%*,
        connect                => $args->{url},
        connect_timeout        => $args->{timeout},
        timeout                => $args->{timeout},
        persistent             => $args->{persistent},
        session                => $args->{session},
        tls_ctx                => $args->{tls_ctx},
        bind_ip                => $args->{bind_ip},
        proxy                  => $args->{proxy},
        on_proxy_connect_error => sub ( $h, $message, $proxy_error ) {
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
            if ( $h->{proxy} && $h->{proxy_type} && $h->{proxy_type} == $PROXY_TYPE_HTTP && $h->{proxy}->userinfo ) {
                $args->{headers}->{PROXY_AUTHORIZATION} = 'Basic ' . $h->{proxy}->userinfo_b64;
            }
            else {
                delete $args->{headers}->{PROXY_AUTHORIZATION};
            }

            $cb->($h);

            return;
        },
    );

    return;
}

sub _write_request ( $args, $runtime ) {
    my $request_path;

    if ( $runtime->{h}->{proxy} && $runtime->{h}->{proxy_type} == $PROXY_TYPE_HTTP ) {    # proxy is HTTP
        $request_path = $args->{url}->to_string;
    }
    else {
        $request_path = $args->{url}->path->to_uri . ( $args->{url}->query ? q[?] . $args->{url}->query : q[] );

        # start TLS, only if TLS is required and TLS is not established yet
        $runtime->{h}->starttls('connect') if $args->{url}->is_secure && !exists $runtime->{h}->{tls};
    }

    # prepare content related headers
    if ( defined $args->{body} ) {
        if ( ref $args->{body} eq 'CODE' ) {
            delete $args->{headers}->{CONTENT_LENGTH};

            $args->{headers}->{TRANSFER_ENCODING} = 'chunked';
        }
        else {
            $args->{headers}->{CONTENT_LENGTH} = bytes::length( ref $args->{body} eq 'SCALAR' ? $args->{body}->$* : $args->{body} );
        }
    }
    else {
        delete $args->{headers}->{CONTENT_LENGTH};

        delete $args->{headers}->{TRANSFER_ENCODING};
    }

    # send request headers
    $runtime->{h}->push_write( "$args->{method} $request_path HTTP/1.1" . $CRLF . $args->{headers}->to_string . $CRLF );

    # return if error occurred during send request headers
    return if !$runtime;

    # send request body
    if ( defined $args->{body} ) {
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
        else {
            $runtime->{h}->push_write( ref $args->{body} ? $args->{body}->$* : $args->{body} );
        }
    }

    return;
}

sub _read_headers ( $args, $runtime, $cb ) {
    $runtime->{h}->read_http_res_headers(
        headers => 1,
        sub ( $h, $res, $error_reason ) {
            if ($error_reason) {
                $runtime->{finish}->( 596, $error_reason );
            }
            else {
                # TODO
                die 'HTTP status 100, 101 are not supporteed correctly yet' if $res->{status} == 100 or $res->{status} == 101;

                # parse SET_COOKIE header, add cookies
                $args->{cookie_jar}->parse_cookies( $args->{url}, $res->{headers}->get('SET_COOKIE') ) if $args->{cookie_jar} && $res->{headers}->{SET_COOKIE};

                # handle redirect
                $runtime->{redirect} = 0;

                if ( exists $res->{headers}->{LOCATION} ) {

                    # parse LOCATION header, create uri object
                    $res->{headers}->{LOCATION} = P->uri( $res->{headers}->{LOCATION}, base => $args->{url} );

                    # this is a redirect
                    if ( exists $REDIRECT->{ $res->{status} } ) {
                        $runtime->{redirect} = 1;

                        # create new response object and set it as default response for current request
                        $runtime->{res} = Pcore::HTTP::Response->new;

                        push $args->{res}->redirect->@*, $runtime->{res};
                    }
                }

                # clean and set content length
                if ( my $cl = delete $res->{headers}->{CONTENT_LENGTH} ) {
                    $cl->[0] =~ s/\s//smg;

                    eval { $runtime->{res}->_set_content_length( $cl->[0] ) } if $cl->[0];
                }

                # fill response object with HTTP response headers data
                $runtime->{res}->{headers} = $res->{headers};

                $runtime->{res}->set_version( q[1.] . $res->{minor_version} );

                $runtime->{res}->set_status( $res->{status}, $res->{reason} );
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

    # check, if content body is expected
    if ( !$chunked && $runtime->{content_length} == 0 ) {

        # if Transfer-Encoding is not chunked and Content-Length is not specified:
        # - if connection is persistent - no content body is expected;
        # - if connection is NOT persistent - read content body unless EOF;
        #
        # HTTP/1.0 if connection is persistent - "Connection: keep-alive" header must be exists;
        # HTTP/1.1 if connection is NOT persistent - "Connection: close" header must be exists;
        # "Transfer-Encoding: chunked" is supported only by HTTP/1.1;

        my $persistent = 1;

        # HTTP/1.1 and no "Connection: close" is present - connection is persistent - no content body is expected
        if ( $runtime->{res}->{version} == 1.1 ) {
            $persistent = 0 if $runtime->{res}->headers->{CONNECTION} && $runtime->{res}->headers->{CONNECTION} =~ /\bclose\b/smi;
        }

        # HTTP/1.0 and "Connection: keep-alive" is present - connection is persistent - no content body is expected
        elsif ( $runtime->{res}->{version} == 1.0 ) {

            # in HTTP/1.0 connection is not persistent by default
            $persistent = 0;

            $persistent = 1 if $runtime->{res}->headers->{CONNECTION} && $runtime->{res}->headers->{CONNECTION} =~ /\bkeep-?alive\b/smi;
        }

        # return and do not read body if connection is persistent
        if ($persistent) {
            $cb->();

            return;
        }
    }

    my $decode;

    if ( $args->{decompress} && $runtime->{res}->headers->{CONTENT_ENCODING} && $runtime->{res}->headers->{CONTENT_ENCODING} =~ /\bgzip\b/smi ) {
        $decode = sub ( $in_buf_ref, $out_buf_ref ) {
            state $x = Compress::Raw::Zlib::Inflate->new( -AppendOutput => 1, -WindowBits => WANT_GZIP_OR_ZLIB );

            state $status;

            if ( defined $in_buf_ref ) {
                $status = $x->inflate( $in_buf_ref, $out_buf_ref );

                return if $status != Z_OK && $status != Z_STREAM_END;    # stream error
            }
            else {
                return if !$status == Z_STREAM_END;                      # stream not finished
            }

            return 1;
        };
    }

    my $on_read;

    if ( $runtime->{redirect} ) {

        # redirects body always readed into memory
        # "on_progress", "on_body" callbacks are ignored (not called)
        my $body = q[];

        $runtime->{res}->set_body( \$body );

        $on_read = sub ( $h, $content_ref, $total_bytes_readed, $error_reason ) {
            state $total_decoded_bytes_readed = 0;

            if ( defined $error_reason ) {
                $cb->( 597, $error_reason );
            }
            else {
                # append buffer
                if ($decode) {
                    if ( !$decode->( $content_ref, \$body ) ) {
                        $cb->( 597, 'Stream decode error' );

                        return;    # stop reading
                    }
                    else {
                        $total_decoded_bytes_readed = length $body;
                    }
                }
                elsif ( defined $content_ref ) {
                    $body .= $content_ref->$*;

                    $total_decoded_bytes_readed = $total_bytes_readed;
                }

                # process callbacks
                if ( defined $content_ref ) {
                    $runtime->{res}->_set_content_length($total_decoded_bytes_readed);

                    return 1;    # continue reading
                }
                else {           # last chunk
                    $cb->();
                }
            }

            return;
        };
    }
    elsif ( $args->{on_body} ) {
        $on_read = sub ( $h, $content_ref, $total_bytes_readed, $error_reason ) {
            state $total_decoded_bytes_readed = 0;

            if ( defined $error_reason ) {
                $cb->( 597, $error_reason );
            }
            else {
                # decode buffer
                if ($decode) {
                    my $out_buf;

                    if ( !$decode->( $content_ref, \$out_buf ) ) {
                        $cb->( 597, 'Stream decode error' );

                        return;    # stop reading
                    }
                    elsif ( defined $content_ref ) {
                        $content_ref = \$out_buf;

                        $total_decoded_bytes_readed += length $content_ref->$*;
                    }
                }
                else {
                    $total_decoded_bytes_readed = $total_bytes_readed;
                }

                # process callbacks
                if ( defined $content_ref ) {
                    $runtime->{res}->_set_content_length($total_decoded_bytes_readed);

                    $args->{on_progress}->( $runtime->{res}, $runtime->{content_length}, $total_bytes_readed ) if $args->{on_progress};

                    if ( $args->{on_body}->( $runtime->{res}, $content_ref, $total_decoded_bytes_readed ) ) {
                        return 1;    # continue reading
                    }
                    else {
                        $cb->( 598, q[Request cancelled by "on_body"] );
                    }
                }
                else {               # last chunk
                    $args->{on_body}->( $runtime->{res}, $content_ref, $total_decoded_bytes_readed );

                    $cb->();
                }
            }

            return;
        };
    }
    else {
        my $body = q[];

        $runtime->{res}->set_body( \$body );

        $on_read = sub ( $h, $content_ref, $total_bytes_readed, $error_reason ) {
            state $total_decoded_bytes_readed = 0;

            state $body_is_fh = 0;

            if ( defined $error_reason ) {
                $cb->( 597, $error_reason );
            }
            else {
                my $out_buf = q[];

                my $out_buf_ref = \$out_buf;

                # append buffer
                if ($decode) {
                    if ( !$decode->( $content_ref, $out_buf_ref ) ) {
                        $cb->( 597, 'Stream decode error' );

                        return;    # stop reading
                    }
                }
                elsif ( defined $content_ref ) {
                    $out_buf_ref = $content_ref;
                }

                # process callbacks
                if ( defined $content_ref ) {
                    $total_decoded_bytes_readed += length $out_buf_ref->$*;

                    if ( $args->{buf_size} && $total_decoded_bytes_readed >= $args->{buf_size} ) {
                        if ( !$body_is_fh ) {
                            $body_is_fh = 1;

                            $runtime->{res}->set_body( P->file->tempfile );

                            if ( length $body ) {
                                syswrite $runtime->{res}->body, $body or die;
                            }

                            undef $body;
                        }
                    }

                    if ( length $out_buf_ref->$* ) {
                        if ($body_is_fh) {
                            syswrite $runtime->{res}->body, $out_buf_ref->$* or die;
                        }
                        else {
                            $runtime->{res}->body->$* .= $out_buf_ref->$*;
                        }
                    }

                    $runtime->{res}->_set_content_length($total_decoded_bytes_readed);

                    $args->{on_progress}->( $runtime->{res}, $runtime->{content_length}, $total_bytes_readed ) if $args->{on_progress};

                    return 1;    # continue reading
                }
                else {           # last chunk
                    $cb->();
                }
            }

            return;
        };
    }

    if ($chunked) {              # read chunked body
        $runtime->{h}->read_http_body( $on_read, chunked => 1, headers => $runtime->{res}->headers );
    }
    elsif ( $runtime->{content_length} ) {    # read body with known content length
        $runtime->{h}->read_http_body( $on_read, length => $runtime->{content_length} );
    }
    else {                                    # read body with unknown content length (until EOF)
        $runtime->{h}->read_http_body($on_read);
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 |                      | Subroutines::ProhibitExcessComplexity                                                                          |
## |      | 23                   | * Subroutine "http_request" with high complexity score (27)                                                    |
## |      | 234                  | * Subroutine "_write_request" with high complexity score (21)                                                  |
## |      | 356                  | * Subroutine "_read_body" with high complexity score (67)                                                      |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 103, 117, 119, 193   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 336                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 567                  | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Util - Pcore::HTTP helper class

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
