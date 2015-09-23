package Pcore::AE::Handle::ProxyPool::Source;

use Pcore qw[-role];
use Pcore::AE::Handle::ProxyPool::Proxy;

requires qw[load];

has pool => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle::ProxyPool'], required => 1, weak_ref => 1 );

has id => ( is => 'lazy', isa => Int, init_arg => undef );

has max_threads_source => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );     # max. num. of threads, allowed simultaneously to all proxies from this source, 0 - any num. of threads allowed
has max_threads_proxy  => ( is => 'ro', isa => PositiveOrZeroInt, default => 20 );
has max_threads_check  => ( is => 'ro', isa => PositiveInt,       default => 20 );    # max. allowed parallel check threads

has load_timeout => ( is => 'ro', isa => Maybe [PositiveOrZeroInt] );                 # undef - use global pool settings, 0 - do not reload

has is_multiproxy => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # proxy can not be banned

has threads => ( is => 'ro', default => 0, init_arg => undef );                       # current threads (running request through this source)

has _load_next_time   => ( is => 'ro', init_arg => undef );
has _load_in_progress => ( is => 'ro', init_arg => undef );

our $_ID = 0;

around load => sub ( $orig, $self ) {

    # reload in progress
    return if $self->{_load_in_progress};

    # not reloadable and already was loaded
    return if !$self->{load_timeout} && $self->{_load_next_time};

    # timeout reached
    return if $self->{_load_next_time} && time < $self->{_load_next_time};

    $self->{_load_in_progress} = 1;

    $self->$orig(
        sub ($uris) {
            my $pool = $self->pool;

            for my $uri ( $uris->@* ) {
                my $proxy = Pcore::AE::Handle::ProxyPool::Proxy->new( $uri, $self );

                # proxy object wasn't created, generally due to uri parsing errors
                next if !$proxy;

                $pool->add_proxy($proxy);
            }

            # update next source load timeout
            $self->{_load_next_time} = time + $self->{load_timeout};

            $self->{_load_in_progress} = 0;

            return;
        }
    );

    return;
};

no Pcore;

sub BUILD ( $self, $args ) {
    die q[You should specify "max_threads_source" or "max_threads_proxy"] if !$self->max_threads_source && !$self->max_threads_proxy;

    return;
}

sub _build_id ($self) {
    return ++$_ID;
}

sub start_thread ($self) {
    return;
}

sub finish_thread ($self) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::ProxyPool::Source

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
