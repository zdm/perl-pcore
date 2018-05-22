package Pcore::Util::Net;

use Pcore;
use Pcore::Util::UUID qw[uuid_v4_str];

sub hostname {
    state $hostname = do {
        require Sys::Hostname;    ## no critic qw[Modules::ProhibitEvilModules]

        Sys::Hostname::hostname();
    };

    return $hostname;
}

sub resolve_listen ($listen) {
    if ( !$listen ) {

        # for windows use TCP loopback
        if ($MSWIN) {
            $listen = '127.0.0.1:' . get_free_port('127.0.0.1');
        }

        # for linux use abstract UDS
        else {
            $listen = "unix:\x00pcore-" . uuid_v4_str;
        }
    }
    else {

        # host without port
        if ( $listen !~ /:/sm ) {
            $listen = "$listen:" . get_free_port( $listen eq '*' ? () : $listen );
        }
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
## |    2 | 26, 47               | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
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
