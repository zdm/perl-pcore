package Pcore::AnyEvent::Proxy::Source;

use Pcore qw[-role];
use Pcore::AnyEvent::Proxy;

requires qw[load];

has max_threads => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );

has _pool => ( is => 'ro', isa => InstanceOf ['Pcore::AnyEvent::Proxy::Pool'], required => 1, weak_ref => 1 );

has is_multiproxy => ( is => 'ro',  isa => Bool, default => 0, init_arg => undef );    # proxy can't be disabled / banned
has threads       => ( is => 'rwp', isa => Int,  default => 0, init_arg => undef );    # current threads (running request through this source)

around load => sub ( $orig, $self, $cv, $temp_pool ) {
    $self->$orig(
        sub ($proxies = undef) {
            if ($proxies) {
                for my $uri ( $proxies->@* ) {
                    push $temp_pool->@*, Pcore::AnyEvent::Proxy->new( { uri => $uri, _source => $self } );
                }
            }

            $cv->end;

            return;
        }
    );

    return;
};

no Pcore;

sub update_proxy_status ( $self, $proxy ) {
    $self->_pool->update_proxy_status($proxy);

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
