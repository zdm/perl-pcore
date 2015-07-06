package Pcore::App::PSGI::Server;

use Pcore qw[-role];

has is_plackup => ( is => 'lazy', isa => Bool, init_arg => undef );
has runner => ( is => 'lazy', isa => InstanceOf ['Plack::Runner'], init_arg => undef );
has server_cfg => ( is => 'lazy', isa => HashRef, init_arg => undef );

our $PSGI_SERVERS = {
    'Feersum' => {
        'pre-fork' => 'workers',
        quiet      => { default => 1 },
    },
    'Starman' => {
        workers             => 'workers',
        backlog             => 'backlog',
        'max-requests'      => 'max_requests',
        'disable-keepalive' => { default => 1 },
        'keepalive-timeout' => { default => 1 },
        'error-log'         => { default => undef },
        'ssl-cert'          => { default => undef },
        'ssl-key'           => { default => undef },
        'enable-ssl'        => { default => undef }
    },
    'Thrall' => {
        'max-workers'        => 'workers',
        timeout              => { default => 300 },
        'keepalive-timeout'  => { default => 2 },
        'max-keepalive-reqs' => { default => 1 },
        'max-reqs-per-child' => 'max_requests',
        'min-reqs-per-child' => { default => undef },
        'spawn-interval'     => { default => undef },
        'main-thread-delay'  => { default => 0.1 }
    },
    'Twiggy'      => {},
    'Twiggy::TLS' => {
        'tls-cert' => { default => undef },
        'tls-key'  => { default => undef },
    },
    'Twiggy::Prefork' => {},
    'Starlet'         => {
        'max-workers'        => 'workers',
        timeout              => { default => 300 },
        'keepalive-timeout'  => { default => 2 },
        'max-keepalive-reqs' => { default => 1 },
        'max-reqs-per-child' => 'max_requests',
        'min-reqs-per-child' => { default => undef },
        'spawn-interval'     => { default => undef }
    },
    'Monoceros' => {
        'max-workers'        => 'workers',
        'max-reqs-per-child' => 'max_requests',
    },
};

sub _build_is_plackup {
    my $self = shift;

    return $ENV{PLACK_ENV} ? 1 : 0;
}

sub _build_server_cfg {
    my $self = shift;

    if ( $self->is_plackup ) {

        # we have no access to real server config if has runned from plackup script
        return {};
    }
    else {
        return P->hash->merge( $self->cfg->{PSGI}->{SERVER}, \%ARGV );
    }
}

sub _build_runner {
    my $self = shift;

    $self->server_cfg->{server} ||= 'Feersum';

    $self->server_cfg->{workers} = P->sys->cpus_num if exists $self->server_cfg->{workers} && !defined $self->server_cfg->{workers};

    my @argv = ('--no-default-middleware');

    push @argv, map { ( '--listen', P->uri($_)->to_psgi ) } $self->server_cfg->{listen}->@* if $self->server_cfg->{listen};
    push @argv, '--env'    => $self->runtime_env;
    push @argv, '--server' => $self->server_cfg->{server};

    for my $key ( keys %{ $PSGI_SERVERS->{ $self->server_cfg->{server} } } ) {
        if ( ref $PSGI_SERVERS->{ $self->server_cfg->{server} }->{$key} eq 'HASH' ) {
            push @argv, ( q[--] . $key => $PSGI_SERVERS->{ $self->server_cfg->{server} }->{$key}->{default} ) if defined $PSGI_SERVERS->{ $self->server_cfg->{server} }->{$key}->{default};
        }
        else {
            push @argv, ( q[--] . $key => $self->server_cfg->{ $PSGI_SERVERS->{ $self->server_cfg->{server} }->{$key} } ) if exists $self->server_cfg->{ $PSGI_SERVERS->{ $self->server_cfg->{server} }->{$key} };
        }
    }

    require Plack::Runner;

    my $runner = Plack::Runner->new;

    $runner->parse_options(@argv);

    return $runner;
}

1;
__END__
=pod

=encoding utf8

=head1 PSGI servers overview

=head1 Recommendations

    |               |  Single process  |        Multi process        |
    |---------------|------------------|-----------------------------|
    | CPU intensive |         -        | Starlet, Starman, Monoceros |
    |---------------|------------------|-----------------------------|
    | Non blocking, | Twiggy,          | Twiggy::Prefork,            |
    | streaming     | Feeersum         | Feersum                     |

=head1 Servers overview

=over

=item Thrall

Preforking with threads. Fork of Starlet.

Features: preforking + threads, SSL, keepalive, IPv6, unix socket

=item Starlight

Preforking, Fork of Thrall with minimun deps, no XS deps.

Features: preforking, SSL, keepalive, IPv6, unix socket

=item Twiggy

Twiggy - AnyEvent HTTP server for PSGI (like Thin)

Features: non-blocking, streaming, unix socket

=item Twiggy::TLS

Fork of Twiggy with SSL support.

Features: SSL

=item Twiggy::Prefork

Twiggy::Prefork is Preforking AnyEvent HTTP server for PSGI based on Twiggy.

Features: preforking, non-blocking, streaming

=item Starman

Starman - High-performance preforking PSGI/Plack web server

Features: preforking, keepalive, unix socket, SSL

=item Starlet

Starlet is a standalone HTTP/1.1 web server.

Features: preforking, keepalive, unix socket

=item Monoceros

Monoceros is PSGI/Plack server supports HTTP/1.1. Monoceros has a event-driven connection manager and preforking workers. Monoceros can keep large amount of connection at minimal processes.

Features: preforking, keepalive

=item Feersum

Feersum is an HTTP server built on EV. It fully supports the PSGI 1.03 spec including the psgi.streaming interface and is compatible with Plack. Feersum uses a single-threaded, event-based programming architecture to scale and can handle many concurrent connections efficiently in both CPU and RAM. It skips doing a lot of sanity checking with the assumption that a "front-end" HTTP/HTTPS server is placed between it and the Internet.

Features: non-blocking, streaming, can be preforking, no keepalive, no SSL, unix socket not supported

=item Corona

Corona is a Coro based Plack web server. It uses Net::Server::Coro under the hood, which means we have coroutines (threads) for each socket, active connections and a main loop. Because it's Coro based your web application can actually block with I/O wait as long as it yields when being blocked, to the other coroutine either explicitly with cede or automatically (via Coro::* magic).

Features: multithread

=item Arriba

Fork of Starman + SPDY support, last updated in 2013.

Features: SPDY

=item Gepok

Preforking. Slow 3 times than Starman.

Features: SSL, unix socket

=back

=cut
