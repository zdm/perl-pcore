package Pcore::Util::Net;

use Pcore;
use Pcore::Util::Scalar qw[is_ref];
use Pcore::Util::UUID qw[uuid_v4_str];

sub hostname {
    state $hostname = do {
        require Sys::Hostname;    ## no critic qw[Modules::ProhibitEvilModules]

        Sys::Hostname::hostname();
    };

    return $hostname;
}

# undef -> //127.0.0.1:rand-port, or ///\x00rand on linux
# //0.0.0.0:90
# //127.0.0.1:* - random port
# /unix-socket-path - absolute unix socket path
# unix-socket-path - relative unix socket path
# \x00unix-socket-name - linux UDS socket
sub resolve_listen ( $listen = undef, $base = undef ) {
    return $listen if is_ref $listen;

    if ( !defined $listen ) {

        # for windows use TCP loopback
        if ($MSWIN) {
            return P->uri( '//127.0.0.1:' . get_free_port('127.0.0.1'), base => $base );
        }

        # for linux use abstract UDS
        else {
            return P->uri( "///\x00" . uuid_v4_str, base => $base );
        }
    }
    else {
        $listen =~ s[([^/:])?:[*]][$1 . ':' . get_free_port($1)]sme;

        return P->uri( $listen, base => $base );
    }

    return $listen;
}

sub get_free_port ($ip = undef) {
    state $init = !!require Socket;

    if ($ip) {
        $ip = Socket::inet_aton $ip;
    }
    else {
        $ip = "\x7f\x00\x00\x01";    # 127.0.0.1
    }

    for ( 1 .. 10 ) {
        socket my $socket, Socket::AF_INET(), Socket::SOCK_STREAM(), 0 or next;

        bind $socket, Socket::pack_sockaddr_in 0, $ip or next;

        my $sockname = getsockname $socket or next;

        my ( $bind_port, $bind_ip ) = Socket::sockaddr_in($sockname);

        return $bind_port;
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
## |    2 | 35, 54               | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Net

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
