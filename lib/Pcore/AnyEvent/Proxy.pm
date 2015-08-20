package Pcore::AnyEvent::Proxy;

use Pcore qw[-class];

has _source => ( is => 'ro', isa => ConsumerOf ['Pcore::AnyEvent::Proxy::Source'], weak_ref => 1 );
has host => ( is => 'ro', isa => Str, required => 1 );
has port => ( is => 'ro', isa => Int, required => 1 );

has is_http    => ( is => 'lazy', isa => Bool, init_arg => 'http' );                      # default type, if no other types are specified
has is_connect => ( is => 'ro',   isa => Bool, default  => 0, init_arg => 'connect' );    # means, that proxy support CONNECT method to ANY port
has is_https   => ( is => 'lazy', isa => Bool, init_arg => 'https' );                     # means, that proxy support CONNECT method ONLY to port 443
has is_socks   => ( is => 'lazy', isa => Bool, init_arg => 'socks' );
has is_socks5  => ( is => 'ro',   isa => Bool, default  => 0, init_arg => 'socks5' );
has is_socks4  => ( is => 'ro',   isa => Bool, default  => 0, init_arg => 'socks4' );
has is_socks4a => ( is => 'ro',   isa => Bool, default  => 0, init_arg => 'socks4a' );

has _active_lists => ( is => 'lazy', isa => ArrayRef, init_arg => undef );

has id           => ( is => 'lazy', isa => Str, init_arg  => undef );                     # [username:password@]host:port
has uri          => ( is => 'lazy', isa => Str, init_arg  => undef );
has authority    => ( is => 'lazy', isa => Str, init_arg  => undef );
has host_port    => ( is => 'lazy', isa => Str, init_arg  => undef );
has userinfo     => ( is => 'lazy', isa => Str, init_arg  => undef );                     # username:password
has username     => ( is => 'ro',   isa => Str, predicate => 1 );
has password     => ( is => 'ro',   isa => Str, predicate => 1 );
has userinfo_b64 => ( is => 'lazy', isa => Str, init_arg  => undef );

has is_disabled => ( is => 'rwp', isa => PositiveOrZeroInt, default => 0, init_arg => undef );    # time, when proxy should be enabled
has is_banned   => ( is => 'rwp', isa => PositiveOrZeroInt, default => 0, init_arg => undef );    # time, when proxy should be unbanned

has threads        => ( is => 'rwp', isa => Int, default => 0, init_arg => undef );               # current threads (running request through this proxy)
has total_requests => ( is => 'rwp', isa => Int, default => 0, init_arg => undef );               # total requests

no Pcore;

sub BUILDARGS ( $self, $args ) {
    if ( $args->{uri} ) {
        my $uri = delete $args->{uri};

        $uri = P->uri( index( $uri, q[//] ) == -1 ? q[//] . $uri : $uri );

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
    }

    if ( $args->{socks} ) {
        $args->{socks5}  = 1;
        $args->{socks4}  = 1;
        $args->{socks4a} = 1;
    }

    return $args;
}

# TYPE BUILDERS
sub _build_is_http ($self) {
    return !$self->is_connect && !$self->is_https && !$self->is_socks ? 1 : 0;
}

sub _build_is_https ($self) {
    return $self->is_connect ? 1 : 0;
}

sub _build_is_socks ($self) {
    return $self->is_socks5 || $self->is_socks4 || $self->is_socks4a ? 1 : 0;
}

# ACTIVE LISTS
sub _build__active_lists ($self) {
    my $lists = {};

    $lists->{http} = 1 if $self->is_http;

    $lists->{connect} = 1 if $self->is_connect;

    $lists->{https} = 1 if $self->is_https;

    $lists->{socks} = 1 if $self->is_socks;

    $lists->{socks5} = 1 if $self->is_socks5;

    return [ keys $lists ];
}

sub _build_id ($self) {
    return $self->authority;
}

sub _build_uri ($self) {
    my @features;

    push @features, 'http' if $self->is_http;

    if ( $self->is_connect ) {
        push @features, 'connect';
    }
    elsif ( $self->is_https ) {
        push @features, 'https';
    }

    push @features, 'socks5' if $self->is_socks5;

    push @features, 'socks4' if $self->is_socks4;

    push @features, 'socks4a' if $self->is_socks4a;

    return ( shift @features ) . '://' . $self->authority . q[?] . join q[&], @features;
}

sub _build_authority ($self) {
    if ( $self->userinfo ) {
        return $self->userinfo . q[@] . $self->host_port;
    }
    else {
        return $self->host_port;
    }
}

# host:port
sub _build_host_port ($self) {
    return $self->host . q[:] . $self->port;
}

sub _build_userinfo ($self) {
    if ( $self->has_username && $self->has_password ) {
        return $self->username . q[:] . $self->password;
    }
    else {
        return q[];
    }
}

sub _build_userinfo_b64 ($self) {
    return P->data->to_b64( $self->userinfo, q[] );
}

# IS ACTIVE
sub is_active ($self) {
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

sub enable ($self) {
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

sub unban ($self) {
    $self->_set_is_banned(0);

    $self->_source->update_proxy_status($self);

    return;
}

# THREADS MANAGEMENT
sub start_thread ($self) {
    $self->_set_threads( $self->threads + 1 );

    $self->_source->_set_threads( $self->_source->threads + 1 );

    $self->_set_total_requests( $self->total_requests + 1 );

    $self->_source->update_proxy_status($self);

    return;
}

sub finish_thread ($self) {
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
## │    3 │ 63                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 179, 201, 224, 236   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AnyEvent::Proxy

=head1 SYNOPSIS

    Pcore::AnyEvent::Proxy->new(
        {   uri   => 'http://user:password@host:9050?connect&socks5',
            socks => 1,
        }
    );

=head1 DESCRIPTION

=cut
