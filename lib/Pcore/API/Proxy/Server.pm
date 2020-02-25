package Pcore::API::Proxy::Server;

use Pcore -class;
use Pcore::API::Proxy;

has listen => '//127.0.0.1';

has proxy => ();    # upstream proxy

has backlog      => 0;
has so_no_delay  => 1;
has so_keepalive => 1;

has _listen_socket => ( init_arg => undef );

sub BUILD ( $self, $args ) {
    $self->{listen} = P->net->parse_listen( $self->{listen} );

    $self->{_listen_socket} = &AnyEvent::Socket::tcp_server(    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
        $self->{listen}->connect,
        sub {
            Coro::async_pool sub { return $self->_on_accept(@_) }, @_;

            return;
        },
        sub {
            return $self->_on_prepare(@_);
        }
    );

    chmod( oct 777, $self->{listen}->{path} ) || die $! if !defined $self->{listen}->{host} && substr( $self->{listen}->{path}, 0, 2 ) ne "/\x00";

    return;
}

sub _on_prepare ( $self, $fh, $host, $port ) {
    return $self->{backlog} // 0;
}

sub _on_accept ( $self, $fh, $host, $port ) {
    my $h = P->handle(
        $fh,
        so_no_delay  => $self->{so_no_delay},
        so_keepalive => $self->{so_keepalive},
    );

    my $chunk = $h->read_chunk(2);
    return if !$h;

    my ( $ver, $nauth ) = unpack 'C*', $chunk->$*;

    return if $ver != 5;

    $chunk = $h->read_chunk($nauth);
    return if !$h;

    $h->write("\x05\x00") or return;

    $chunk = $h->read_chunk(4);
    return if !$h;

    ( $ver, my $cmd, my $rsv, my $type ) = unpack 'C*', $chunk->$*;

    my ( $target_host, $target_port );

    # TODO ipv4, 4 bytes
    if ( $type == 1 ) {
        $chunk = $h->read_chunk(6);
        return if !$h;

        die 'ipv4 not implemented';
    }

    # domain, 1 byte of name length followed by 1–255 bytes the domain name
    elsif ( $type == 3 ) {
        $chunk = $h->read_chunk(1);
        return if !$h;

        my $len = unpack 'C*', $chunk->$*;

        $chunk = $h->read_chunk( $len + 2 );
        return if !$h;

        ( $target_host, $target_port ) = unpack "a[$len]n", $chunk->$*;
    }

    # TODO ipv6, 16 bytes
    elsif ( $type == 4 ) {
        $chunk = $h->read_chunk(18);
        return if !$h;

        die 'ipv6 not implemented';
    }
    else {
        return;
    }

    my $proxy_h;

    # establish a TCP/IP stream connection
    if ( $cmd == 1 ) {
        if ( $self->{proxy} ) {
            my $proxy = Pcore::API::Proxy->new( $self->{proxy} );

            $proxy_h = $proxy->connect_socks5("//$target_host:$target_port");
        }
        else {
            $proxy_h = P->handle("tcp://$target_host:$target_port");
        }

        if ( !$proxy_h ) {
            return;
        }
        else {
            $h->write( "\x05\x00\x00\x03" . pack( 'C', length $target_host ) . $target_host . pack( 'n', $target_port ) ) or return;
        }
    }

    # TODO establish a TCP/IP port binding
    elsif ( $cmd == 2 ) {
        die 'not supported';
    }

    # TODO associate a UDP port
    elsif ( $cmd == 3 ) {
        die 'not supported';
    }
    else {
        return;
    }

    $self->_run_tunnel( $h, $proxy_h );

    return;
}

sub _run_tunnel ( $self, $h1, $h2 ) {

    # listen browser
    Coro::async_pool {
        while () {
            my $buf = $h1->read( timeout => undef );

            last             if !$h2;
            $h2->write($buf) if $buf;

            last if !$h1;
        }

        $h2->shutdown;
        $h2->close;

        return;
    };

    # listen proxy
    Coro::async_pool {
        while () {
            my $buf = $h2->read( timeout => undef );

            last             if !$h1;
            $h1->write($buf) if $buf;

            last if !$h2;
        }

        $h1->shutdown;
        $h1->close;

        return;
    };

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 40                   | Subroutines::ProhibitExcessComplexity - Subroutine "_on_accept" with high complexity score (23)                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 115                  | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Proxy::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
