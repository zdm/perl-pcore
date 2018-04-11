package Pcore::AE::Patch;

use Pcore;
use Socket qw(AF_INET AF_UNIX SOCK_STREAM SOCK_DGRAM SOL_SOCKET SO_REUSEADDR);
use AnyEvent qw[];
use AnyEvent::Socket qw[];
use AnyEvent::Util qw[guard];

our $TTL            = 60;       # cache positive responses for 60 sec.
our $NEGATIVE_TTL   = 5;        # cache negative responses for 5 sec.
our $MAX_CACHE_SIZE = 10_000;

our $SOCKADDR_CACHE = {};

# condvar patch
{
    no warnings qw[redefine];

    sub AnyEvent::CondVar::recv {
        unless ( $_[0]{_ae_sent} ) {
            Carp::croak q[AnyEvent::CondVar: second block attempted on the same cv] if $_[0]{_is_waiting};

            $_[0]{_is_waiting} = 1;

            if ($AnyEvent::CondVar::Base::WAITING) {
                $_[0]{_rouse_cb} = Coro::rouse_cb;

                Coro::rouse_wait $_[0]{_rouse_cb};
            }
            else {
                local $AnyEvent::CondVar::Base::WAITING = 1;

                $_[0]->_wait;
            }

            $_[0]{_is_waiting} = 0;
        }

        $_[0]{_ae_croak} and Carp::croak $_[0]{_ae_croak};

        return wantarray ? @{ $_[0]{_ae_sent} } : $_[0]{_ae_sent}[0];
    }

    sub AnyEvent::CondVar::send {
        my $cv = shift;

        $cv->{_ae_sent} = [@_];

        ( delete $cv->{_ae_cb} )->($cv) if $cv->{_ae_cb};

        if ( my $rouse_cb = delete $cv->{_rouse_cb} ) {
            $rouse_cb->();

            return;
        }
        else {
            return $cv->_send;
        }
    }
}

*AnyEvent::Socket::resolve_sockaddr_orig = \&AnyEvent::Socket::resolve_sockaddr;
*AnyEvent::Socket::_tcp_bind_orig        = \&AnyEvent::Socket::_tcp_bind;

# install hooks
{
    no warnings qw[redefine];

    *AnyEvent::Socket::resolve_sockaddr = \&resolve_sockaddr;
    *AnyEvent::Socket::_tcp_bind        = \&_tcp_bind;
}

# support for linux abstract UDS
# cache requests
sub resolve_sockaddr ( $node, $service, $proto, $family, $type, $cb ) : prototype($$$$$$) {
    state $callback = {};

    if ( $node eq 'unix/' ) {

        # error
        return $cb->() if $family || $service !~ /^[\/\x00]/sm;

        return $cb->( [ AF_UNIX, defined $type ? $type : SOCK_STREAM, 0, Socket::pack_sockaddr_un $service] );
    }

    my $cache_key = join q[-], map { $_ // q[] } @_[ 0 .. $#_ - 1 ];

    if ( exists $SOCKADDR_CACHE->{$cache_key} ) {
        if ( $SOCKADDR_CACHE->{$cache_key}->[0] > time ) {
            $cb->( $SOCKADDR_CACHE->{$cache_key}->[1]->@* );

            return;
        }
        else {
            delete $SOCKADDR_CACHE->{$cache_key};
        }
    }

    push $callback->{$cache_key}->@*, $cb;

    return if $callback->{$cache_key}->@* > 1;

    AnyEvent::Socket::resolve_sockaddr_orig(
        @_[ 0 .. $#_ - 1 ],
        sub (@) {

            # cleanup cache
            $SOCKADDR_CACHE = {} if keys $SOCKADDR_CACHE->%* > $MAX_CACHE_SIZE;

            # cache response
            $SOCKADDR_CACHE->{$cache_key} = [ time + ( @_ ? $TTL : $NEGATIVE_TTL ), \@_ ];

            # fire callbacks
            while ( my $cb = shift $callback->{$cache_key}->@* ) {
                $cb->(@_);
            }

            delete $callback->{$cache_key};

            return;
        }
    );

    return;
}

# support for linux abstract UDS
sub _tcp_bind ( $host, $service, $done, $prepare = undef ) : prototype($$$;$) {

    # hook for Linux abstract Unix Domain Sockets (UDS)
    if ( defined $host && $host eq 'unix/' && substr( $service, 0, 1 ) eq "\x00" ) {
        state $ipn_uds = pack 'S', AF_UNIX;

        my %state;

        socket $state{fh}, AF_UNIX, SOCK_STREAM, 0 or die "tcp_server/socket: $!";

        bind $state{fh}, AnyEvent::Socket::pack_sockaddr $service, $ipn_uds or die "bind: $!";

        AnyEvent::fh_unblock $state{fh};

        my $len;

        $len = $prepare->( $state{fh}, AnyEvent::Socket::format_address $ipn_uds, $service ) if $prepare;

        $len ||= 128;

        listen $state{fh}, $len or die "listen: $!";

        $done->( \%state );

        return defined wantarray ? guard { %state = () } : ();
    }

    return AnyEvent::Socket::_tcp_bind_orig(@_);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 63, 70               | Variables::ProtectPrivateVars - Private variable used                                                          |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 75                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 155                  | Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 131                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Patch

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
