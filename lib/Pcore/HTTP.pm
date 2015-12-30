package Pcore::HTTP;

use Pcore -const,
  -export => {
    ALL     => [qw[http_request http_head http_get http_post http_mirror]],
    TLS_CTX => [qw[$TLS_CTX_HIGH $TLS_CTX_LOW]],
  };
use Pcore::Util::Scalar qw[blessed is_glob];
use Pcore::AE::Handle qw[:PERSISTENT];
use Pcore::HTTP::Util;
use Pcore::HTTP::Message::Headers;
use Pcore::HTTP::Response;
use Pcore::HTTP::CookieJar;

no Pcore;

const our $TLS_CTX_LOW  => 1;
const our $TLS_CTX_HIGH => 2;
const our $TLS_CTX      => {
    $TLS_CTX_LOW  => { cache => 1, sslv2  => 1 },
    $TLS_CTX_HIGH => { cache => 1, verify => 1, verify_peername => 'https' },
};

our $DEFAULT = {
    method   => undef,
    url      => undef,
    blocking => undef,

    useragent         => "Mozilla/5.0 (compatible; U; Pcore-HTTP-UA/$Pcore::VERSION",
    recurse           => 7,                                                             # max. redirects
    timeout           => 300,                                                           # timeout in seconds
    accept_compressed => 1,                                                             # add ACCEPT_ENCODIING header
    decompress        => 1,                                                             # automatically decompress
    persistent        => $PERSISTENT_IDENT,
    session           => undef,
    cookie_jar        => undef,                                                         # 1 - create cookie jar object automatically
    proxy             => undef,

    # write body to fh if body length > this value, 0 - always store in memory, 1 - always store to file
    buf_size => 0,

    tls_ctx       => $TLS_CTX_LOW,
    handle_params => undef,

    headers => undef,
    body    => undef,

    # 1 - create progress indicator, HashRef - progress indicator params, CodeRef - on_progress callback
    on_progress => undef,
    on_header   => undef,
    on_body     => undef,
    on_finish   => undef,
};

our $DEFAULT_HANDLE_PARAMS = {    #
    max_read_size => 1_048_576,
};

# $method => [$idempotent, $safe]
const our $HTTP_METHODS => {
    ACL                => [ 1, 0 ],
    'BASELINE-CONTROL' => [ 1, 0 ],
    BIND               => [ 1, 0 ],
    CHECKIN            => [ 1, 0 ],
    CHECKOUT           => [ 1, 0 ],
    CONNECT            => [ 0, 0 ],
    COPY               => [ 1, 0 ],
    DELETE             => [ 1, 0 ],
    GET                => [ 1, 1 ],
    HEAD               => [ 1, 1 ],
    LABEL              => [ 1, 0 ],
    LINK               => [ 1, 0 ],
    LOCK               => [ 0, 0 ],
    MERGE              => [ 1, 0 ],
    MKACTIVITY         => [ 1, 0 ],
    MKCALENDAR         => [ 1, 0 ],
    MKCOL              => [ 1, 0 ],
    MKREDIRECTREF      => [ 1, 0 ],
    MKWORKSPACE        => [ 1, 0 ],
    MOVE               => [ 1, 0 ],
    OPTIONS            => [ 1, 1 ],
    ORDERPATCH         => [ 1, 0 ],
    PATCH              => [ 0, 0 ],
    POST               => [ 0, 0 ],
    PRI                => [ 1, 1 ],
    PROPFIND           => [ 1, 1 ],
    PROPPATCH          => [ 1, 0 ],
    PUT                => [ 1, 0 ],
    REBIND             => [ 1, 0 ],
    REPORT             => [ 1, 1 ],
    SEARCH             => [ 1, 1 ],
    TRACE              => [ 1, 1 ],
    UNBIND             => [ 1, 0 ],
    UNCHECKOUT         => [ 1, 0 ],
    UNLINK             => [ 1, 0 ],
    UNLOCK             => [ 1, 0 ],
    UPDATE             => [ 1, 0 ],
    UPDATEREDIRECTREF  => [ 1, 0 ],
    'VERSION-CONTROL'  => [ 1, 0 ],
};

# create aliases for export
*http_request = \&request;
*http_head    = \&head;
*http_get     = \&get;
*http_post    = \&post;
*http_mirror  = \&mirror;

sub ua {
    state $init = !!require Pcore::HTTP::Request;

    return Pcore::HTTP::Request->new(@_);
}

sub request ( $method, $url, @ ) {
    return _request( splice( @_, 2 ), method => $method, url => $url );
}

sub head ( $url, @ ) {
    return _request( 'url', @_, method => 'HEAD' );
}

sub get ( $url, @ ) {
    return _request( 'url', @_, method => 'GET' );
}

sub post ( $url, @ ) {
    return _request( 'url', @_, method => 'POST' );
}

# mirror($target_path, $url, $params) or mirror($target_path, $method, $url, $params)
# additional params supported:
# no_cache => 1;
sub mirror ( $target, @ ) {
    my ( $method, $url, %args );

    if ( exists $HTTP_METHODS->{ $_[1] } ) {
        ( $method, $url, %args ) = splice @_, 1;
    }
    else {
        $method = 'GET';

        ( $url, %args ) = splice @_, 1;
    }

    $args{buf_size} = 1;

    $args{headers}->{IF_MODIFIED_SINCE} = P->date->from_epoch( [ stat $target ]->[9] )->to_http_date if !$args{no_cache} && -f $target;

    my $on_finish = delete $args{on_finish};

    $args{on_finish} = sub ($res) {
        if ( $res->status == 200 ) {
            P->file->move( $res->body->path, $target );

            if ( my $last_modified = $res->headers->{LAST_MODIFIED} ) {
                my $mtime = P->date->parse($last_modified)->at_utc->epoch;

                utime $mtime, $mtime, $target or die;
            }
        }

        $on_finish->($res) if $on_finish;

        return;
    };

    return _request( %args, method => $method, url => $url );
}

sub _request {
    my %args;

    if ( !blessed $_[0] ) {
        %args = ( $DEFAULT->%*, @_ );

        $args{headers} = blessed $args{headers} ? $args{headers}->clone : Pcore::HTTP::Message::Headers->new->replace( $args{headers} ) if $args{headers};
    }
    else {
        while (@_) {
            my $old_headers = delete $args{headers};

            if ( blessed $_[0] ) {
                my $obj = shift;

                for my $arg ( keys $DEFAULT->%* ) {
                    $args{$arg} = $obj->$arg;
                }

                $args{headers} = $args{headers} ? $old_headers->replace( $args{headers}->get_hash ) : $old_headers if $old_headers;
            }
            else {
                %args = ( %args, @_ );

                # headers were aadded
                if ($old_headers) {
                    $args{headers} = $args{headers} ? $old_headers->replace( blessed $args{headers} ? $args{headers}->get_hash : $args{headers} ) : $old_headers;
                }

                # headers were created
                elsif ( $args{headers} ) {
                    $args{headers} = blessed $args{headers} ? $args{headers}->clone : Pcore::HTTP::Message::Headers->new->replace( $args{headers} );
                }

                last;
            }
        }
    }

    # create empty headers object if no headers were added
    $args{headers} = Pcore::HTTP::Message::Headers->new if !$args{headers};

    $args{res} = Pcore::HTTP::Response->new;

    $args{url} = P->uri( $args{url}, base => 'http://', authority => 1 ) if !ref $args{url};

    # merge handle_params
    if ( my $handle_params = delete $args{handle_params} ) {
        $args{handle_params} = {    #
            $DEFAULT_HANDLE_PARAMS->%*,
            $handle_params->%*,
        };
    }
    else {
        $args{handle_params} = $DEFAULT_HANDLE_PARAMS;
    }

    # apply useragent
    if ( my $useragent = delete $args{useragent} ) {
        $args{headers}->{USER_AGENT} = $useragent if !exists $args{headers}->{USER_AGENT};
    }

    # resolve cookie_jar shortcut
    $args{cookie_jar} = Pcore::HTTP::CookieJar->new if $args{cookie_jar} && !ref $args{cookie_jar};

    # resolve TLS context shortcut
    $args{tls_ctx} = $TLS_CTX->{ $args{tls_ctx} } if !ref $args{tls_ctx};

    # resolve on_progress shortcut
    if ( $args{on_progress} && ref $args{on_progress} ne 'CODE' ) {
        if ( !ref $args{on_progress} ) {
            $args{on_progress} = _get_on_progress_cb();
        }
        elsif ( ref $args{on_progress} eq 'HASH' ) {
            $args{on_progress} = _get_on_progress_cb( $args{on_progress}->%* );
        }
        else {
            die q["on_progress" can be CodeRef, HashRef or "1"];
        }
    }

    # prepare body
    if ( defined $args{body} ) {
        if ( ref $args{body} eq 'CODE' ) {
            delete $args{headers}->{CONTENT_LENGTH};

            $args{headers}->{TRANSFER_ENCODING} = 'chunked';
        }
        else {
            $args{headers}->{CONTENT_LENGTH} = bytes::length( ref $args{body} eq 'SCALAR' ? $args{body}->$* : $args{body} );
        }
    }

    # blocking cv
    my $cv = delete $args{blocking};

    my $blocking;

    if ( $cv && !ref $cv ) {
        $cv = AE::cv;

        $blocking = 1;
    }

    # on_finish wrapper
    my $on_finish = delete $args{on_finish};

    my $res = $args{res};

    $args{on_finish} = sub {

        # rewind body fh
        $res->body->seek( 0, 0 ) if $res->has_body && is_glob( $res->body );

        # on_finish callback
        $on_finish->($res) if $on_finish;

        $cv->end if $cv;

        return;
    };

    $cv->begin if $cv;

    # throw request
    Pcore::HTTP::Util::http_request( \%args );

    $cv->recv if $cv && $blocking;

    return;
}

sub _get_on_progress_cb (%args) {
    return sub ( $res, $content_length, $bytes_received ) {
        state $indicator;

        if ( !$bytes_received ) {    # called after headers received
            $args{network} = 1;

            $args{total} = $content_length;

            $indicator = P->progress->get_indicator(%args);
        }
        else {
            $indicator->update( value => $bytes_received );
        }

        return;
    };
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 171                  │ Subroutines::ProhibitExcessComplexity - Subroutine "_request" with high complexity score (43)                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 175, 186, 220, 221,  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 245                  │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 157                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
