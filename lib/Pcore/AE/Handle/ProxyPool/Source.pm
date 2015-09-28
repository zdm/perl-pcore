package Pcore::AE::Handle::ProxyPool::Source;

use Pcore qw[-role];
use Pcore::AE::Handle::ProxyPool::Proxy;

requires qw[load];

has pool => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle::ProxyPool'], required => 1, weak_ref => 1 );
has id => ( is => 'lazy', isa => Int, init_arg => undef );

has load_timeout          => ( is => 'lazy', isa => PositiveOrZeroInt );
has connect_error_timeout => ( is => 'lazy', isa => PositiveInt );
has max_connect_errors    => ( is => 'lazy', isa => PositiveInt );
has max_threads_proxy     => ( is => 'lazy', isa => PositiveOrZeroInt );
has max_threads_source    => ( is => 'lazy', isa => PositiveOrZeroInt );
has is_multiproxy         => ( is => 'ro',   isa => Bool, default => 0 );    # proxy can not be banned

has threads => ( is => 'ro', default => 0, init_arg => undef );              # current threads (running request through this source)
has total_threads => ( is => 'ro', isa => Int, default => 0, init_arg => undef );    # total connections was made through this source

has _load_next_time   => ( is => 'ro', init_arg => undef );
has _load_in_progress => ( is => 'ro', init_arg => undef );

# has _waiting_callbacks => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );

around load => sub ( $orig, $self ) {

    # reload in progress
    return if $self->{_load_in_progress};

    # not reloadable and already was loaded
    return if !$self->load_timeout && $self->{_load_next_time};

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
            $self->{_load_next_time} = time + $self->load_timeout;

            $self->{_load_in_progress} = 0;

            return;
        }
    );

    return;
};

no Pcore;

# BUILDERS
sub _build_id ($self) {
    state $id = 0;

    return ++$id;
}

sub _build_load_timeout ($self) {
    return $self->pool->load_timeout;
}

sub _build_connect_error_timeout ($self) {
    return $self->pool->connect_error_timeout;
}

sub _build_max_connect_errors ($self) {
    return $self->pool->max_connect_errors;
}

sub _build_max_threads_proxy ($self) {
    return $self->pool->max_threads_proxy;
}

sub _build_max_threads_source ($self) {
    return $self->pool->max_threads_source;
}

# METHODS
sub can_connect ($self) {
    return 0 if $self->max_threads_source && $self->{threads} >= $self->max_threads_source;

    return 1;
}

sub start_thread ($self) {
    $self->{threads}++;

    $self->{total_threads}++;

    # disable source if max. source threads limit exceeded
    $self->pool->storage->disable_source($self) if !$self->can_connect;

    return;
}

sub finish_thread ($self) {
    my $old_can_connect = $self->can_connect;

    $self->{threads}--;

    my $can_connect = $self->can_connect;

    if ( $can_connect && $can_connect != $old_can_connect ) {

        # enable source, if was disabled previously
        $self->pool->storage->enable_source($self);

        # source is free, call waiting callbacks
        # for ( $self->_waiting_callbacks->@* ) {
        #     last if $_->[0]->_on_status_change;
        # }

    }

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
