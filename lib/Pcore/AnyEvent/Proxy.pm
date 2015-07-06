package Pcore::AnyEvent::Proxy;

use Pcore qw[-class];

has _source => ( is => 'ro', isa => ConsumerOf ['Pcore::AnyEvent::Proxy::Source'], weak_ref => 1 );

has is_http    => ( is => 'lazy', isa => Bool, init_arg => 'http' );
has is_https   => ( is => 'ro',   isa => Bool, default  => 0, init_arg => 'https' );     # means, that proxy support CONNECT method
has is_socks   => ( is => 'lazy', isa => Bool, init_arg => 'socks' );
has is_socks5  => ( is => 'ro',   isa => Bool, default  => 0, init_arg => 'socks5' );
has is_socks4  => ( is => 'ro',   isa => Bool, default  => 0, init_arg => 'socks4' );
has is_socks4a => ( is => 'ro',   isa => Bool, default  => 0, init_arg => 'socks4a' );

has _active_lists => ( is => 'lazy', isa => ArrayRef, init_arg => undef );

has id        => ( is => 'lazy', isa => Str, init_arg  => undef );                       # host:port
has addr      => ( is => 'lazy', isa => Str, init_arg  => undef );                       # [username:password@]host:port
has host_port => ( is => 'lazy', isa => Str, init_arg  => undef );
has host      => ( is => 'ro',   isa => Str, required  => 1 );
has port      => ( is => 'ro',   isa => Int, required  => 1 );
has auth      => ( is => 'lazy', isa => Str, init_arg  => undef );
has username  => ( is => 'ro',   isa => Str, predicate => 1 );
has password  => ( is => 'ro',   isa => Str, predicate => 1 );
has auth_b64  => ( is => 'lazy', isa => Str, init_arg  => undef );

has uri         => ( is => 'lazy', isa => Str, init_arg => undef );
has http_uri    => ( is => 'lazy', isa => Str, init_arg => undef );
has https_uri   => ( is => 'lazy', isa => Str, init_arg => undef );
has socks_uri   => ( is => 'lazy', isa => Str, init_arg => undef );
has socks5_uri  => ( is => 'lazy', isa => Str, init_arg => undef );
has socks4_uri  => ( is => 'lazy', isa => Str, init_arg => undef );
has socks4a_uri => ( is => 'lazy', isa => Str, init_arg => undef );

has socks_ver => ( is => 'lazy', isa => Str, init_arg => undef );

has is_disabled => ( is => 'rwp', isa => PositiveOrZeroInt, default => 0, init_arg => undef );    # time, when proxy should be enabled
has is_banned   => ( is => 'rwp', isa => PositiveOrZeroInt, default => 0, init_arg => undef );    # time, when proxy should be unbanned

has threads        => ( is => 'rwp', isa => Int, default => 0, init_arg => undef );               # current threads (running request through this proxy)
has total_requests => ( is => 'rwp', isa => Int, default => 0, init_arg => undef );               # total requests

no Pcore;

sub parse_uri ( $self, $uri ) {
    $uri = q[//] . $uri if index( $uri, q[//] ) == -1;

    $uri = P->uri($uri);

    my $args = {};

    # analyze proxy scheme, add corresponding feature
    $args->{ $uri->scheme } = 1 if $uri->scheme;

    # analyse username:password@...
    $args->{username} = $uri->username if $uri->username;

    $args->{password} = $uri->password if $uri->password;

    # analyse host:port...
    $args->{host} = $uri->host if $uri->host;

    if ( $uri->port ) {
        if ( index( $uri->port, q[:] ) != -1 ) {
            ( $args->{port}, $args->{username}, $args->{password} ) = split /:/sm, $uri->port;
        }
        else {
            $args->{port} = $uri->port;
        }
    }

    if ( $uri->query ) {
        for ( keys $uri->query_params->%* ) {
            $args->{$_} = 1;
        }
    }

    return $args;
}

sub BUILDARGS {
    my $self = shift;
    my $args = shift;

    if ( $args->{socks} ) {
        $args->{socks5}  = 1;
        $args->{socks4}  = 1;
        $args->{socks4a} = 1;
    }

    return $args;
}

# TYPE BUILDERS
sub _build_is_http {
    my $self = shift;

    return 1 if !$self->is_https && !$self->is_socks;

    return 0;
}

sub _build_is_socks {
    my $self = shift;

    return 1 if $self->is_socks5 || $self->is_socks4 || $self->is_socks4a;

    return 0;
}

# ACTIVE LISTS
sub _build__active_lists {
    my $self = shift;

    my $lists = {};

    if ( $self->is_http ) {
        $lists->{http} = 1;
    }

    if ( $self->is_https ) {
        $lists->{https} = 1;
    }

    if ( $self->is_socks ) {
        $lists->{http}  = 1;
        $lists->{https} = 1;
        $lists->{socks} = 1;
    }

    return [ keys $lists ];
}

# [username:password@]host:port
sub _build_id {
    my $self = shift;

    return $self->addr;
}

# [username:password@]host:port
sub _build_addr {
    my $self = shift;

    if ( $self->auth ) {
        return $self->auth . q[@] . $self->host_port;
    }
    else {
        return $self->host_port;
    }
}

# host:port
sub _build_host_port {
    my $self = shift;

    return $self->host . q[:] . $self->port;
}

# username:password
sub _build_auth {
    my $self = shift;

    if ( $self->has_username && $self->has_password ) {
        return $self->username . q[:] . $self->password;
    }
    else {
        return q[];
    }
}

sub _build_auth_b64 {
    my $self = shift;

    return P->data->to_b64( $self->auth, q[] );
}

# URI BUILDERS
sub _build_uri ($self) {
    my @features;

    push @features, 'http' if $self->is_http;

    push @features, 'https' if $self->is_https;

    push @features, 'socks5' if $self->is_socks5;

    push @features, 'socks4' if $self->is_socks4;

    push @features, 'socks4a' if $self->is_socks4a;

    return ( shift @features ) . '://' . $self->addr . q[?] . join q[&], @features;
}

sub _build_http_uri ($self) {
    return q[] unless $self->is_http;

    return 'http://' . $self->addr;
}

sub _build_https_uri ($self) {
    return q[] unless $self->is_https;

    return 'https://' . $self->addr;
}

sub _build_socks_uri ($self) {
    return q[] unless $self->is_socks;

    my @features;

    push @features, 'socks5' if $self->is_socks5;

    push @features, 'socks4' if $self->is_socks4;

    push @features, 'socks4a' if $self->is_socks4a;

    return ( shift @features ) . '://' . $self->addr . ( @features ? q[?] . join q[&], @features : q[] );
}

sub _build_socks5_uri ($self) {
    return q[] unless $self->is_socks5;

    return 'socks5://' . $self->addr;
}

sub _build_socks4_uri ($self) {
    return q[] unless $self->is_socks4;

    return 'socks4://' . $self->addr;
}

sub _build_socks4a_uri ($self) {
    return q[] unless $self->is_socks4a;

    return 'socks4a://' . $self->addr;
}

sub _build_socks_ver ($self) {
    my $ver = q[];

    if ( $self->is_socks ) {
        if ( $self->is_socks5 ) {
            $ver = q[5];
        }
        elsif ( $self->is_socks4 ) {
            $ver = q[4];
        }
        elsif ( $self->is_socks4a ) {
            $ver = q[4a];
        }
    }

    return $ver;
}

# IS ACTIVE
sub is_active {
    my $self = shift;

    my $is_active = !$self->is_disabled && !$self->is_banned;

    if ( $is_active && $self->_source->max_threads ) {
        if ( $self->_source->is_multiproxy ) {
            $is_active = 0 if $self->_source->threads >= $self->_source->max_threads;
        }
        else {
            $is_active = 0 if $self->threads >= $self->_source->max_threads;
        }
    }

    return $is_active;
}

# ENABLED / DISABLED
sub disable {
    my $self = shift;
    my $timeout = shift // $self->_source->_pool->disable_timeout;

    return if !$timeout || $self->_source->is_multiproxy;

    $self->_set_is_disabled( time + $timeout );

    $self->_source->update_proxy_status($self);

    return;
}

sub enable {
    my $self = shift;

    $self->_set_is_disabled(0);

    $self->_source->update_proxy_status($self);

    return;
}

# BAN
sub ban {
    my $self = shift;
    my $timeout = shift // $self->_source->_pool->ban_timeout;

    return if !$timeout || $self->_source->is_multiproxy;

    $self->_set_is_banned( time + $timeout );

    $self->_source->update_proxy_status($self);

    return;
}

sub unban {
    my $self = shift;

    $self->_set_is_banned(0);

    $self->_source->update_proxy_status($self);

    return;
}

# THREADS MANAGEMENT
sub start_thread {
    my $self = shift;

    $self->_set_threads( $self->threads + 1 );

    $self->_source->_set_threads( $self->_source->threads + 1 );

    $self->_set_total_requests( $self->total_requests + 1 );

    $self->_source->update_proxy_status($self);

    return;
}

sub finish_thread {
    my $self = shift;

    $self->_set_threads( $self->threads - 1 ) if $self->threads > 0;

    $self->_source->_set_threads( $self->_source->threads - 1 ) if $self->_source->threads > 0;

    $self->_source->update_proxy_status($self);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 72                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 277, 301, 328, 342   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
