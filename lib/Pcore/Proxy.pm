package Pcore::Proxy v0.1.0;

use Pcore qw[-class];

extends qw[Pcore::Util::URI];

has id      => ( is => 'lazy', isa => Str, init_arg => undef );
has refaddr => ( is => 'lazy', isa => Int, init_arg => undef );

has is_enabled => ( is => 'ro', default => 1, init_arg => undef );    # can connect to the proxy
has is_deleted => ( is => 'ro', default => 0, init_arg => undef );    # proxy is removed from pool

has is_http    => ( is => 'ro', isa => Maybe [Bool], init_arg => undef );    # undef - not tested
has is_connect => ( is => 'ro', isa => Maybe [Bool], init_arg => undef );
has is_socks5  => ( is => 'ro', isa => Maybe [Bool], init_arg => undef );
has is_socks4  => ( is => 'ro', isa => Maybe [Bool], init_arg => undef );
has is_socks4a => ( is => 'ro', isa => Maybe [Bool], init_arg => undef );

# 'scheme:connect_port' => proxy_connect_type || 0, if connection is not suported, !exists || undef - not tested yet
has tested_connections => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

around new => sub ( $orig, $self, $uri ) {
    if ( my $args = $self->_parse_uri($uri) ) {
        $self->$orig($args);
    }
    else {
        return;
    }
};

no Pcore;

sub _parse_uri ( $self, $uri ) {
    $uri = q[//] . $uri if index( $uri, q[//] ) == -1;

    my $args = $self->_parse_uri_string($uri);

    if ( $args->{authority} ) {

        # parse userinfo
        my @token = split /:/sm, $args->{authority};

        if ( @token < 2 ) {

            # port should be specified
            return;
        }
        elsif ( @token == 4 ) {

            # host:port:username:password
            $args->{authority} = $token[2] . q[:] . $token[3] . q[@] . $token[0] . q[:] . $token[1];
        }
        elsif ( @token > 4 ) {
            return;
        }

        return $args;
    }
    else {
        return;
    }
}

sub _build_id ($self) {
    return $self->hostport;
}

sub start_thread ($self) {
    $self->{threads}++;

    return;
}

sub finish_thread ($self) {
    $self->{threads}--;

    return;
}

sub disable ( $self, $timeout = undef ) {
    return;
}

sub ban ( $self, $key, $timeout = undef ) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy - Proxy lists management subsystem

=head1 SYNOPSIS

    use Pcore::Proxy::Pool;

    my $pool = Pcore::Proxy::Pool->new(
        {   source => [
                {   class => 'Tor',
                    host  => '192.168.175.1',
                    port  => 9050,
                },
                {   class   => 'List',
                    proxies => [         #
                        'connect://107.153.45.156:80',
                        'connect://23.247.255.3:80',
                        'connect://23.247.255.2:80',
                        'connect://104.144.28.45:80',
                        'connect://107.173.180.52:80',
                        'connect://155.94.218.158:80',
                        'connect://155.94.218.160:80',
                        'connect://198.23.216.57:80',
                        'connect://172.245.109.210:80',
                        'connect://107.173.180.156:80',
                    ],
                },
            ],
        }
    );

    $pool->get_proxy(
        ['connect', 'socks'],
        sub ($proxy = undef) {
            ...;

            return;
        }
    );

=head1 DESCRIPTION

=cut
