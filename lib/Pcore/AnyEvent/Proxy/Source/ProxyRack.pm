package Pcore::AnyEvent::Proxy::Source::ProxyRack;

use Pcore qw[-class];

with qw[Pcore::AnyEvent::Proxy::Source];

has host_port => ( is => 'ro', isa => Str, predicate => 1 );
has type => ( is => 'ro', isa => Enum [qw[ANY FASTEST TOP10]], default => 'FASTEST' );    # TOP10 - top 10% of all proxies

has '+max_threads' => ( isa => Enum [ 50, 100, 200 ], default => 50 );
has '+is_multiproxy' => ( default => 1 );

no Pcore;

sub load ( $self, $cb ) {
    my $proxies;

    if ( $self->host_port ) {
        push $proxies->@*, q[//] . $self->host_port . '?http&connect&socks';
    }
    else {
        if ( $self->type eq 'ANY' ) {
            push $proxies->@*, '//37.58.52.41:2020?http&connect&socks';
        }
        elsif ( $self->type eq 'FASTEST' ) {
            push $proxies->@*, '//37.58.52.41:3030?http&connect&socks';
        }
        elsif ( $self->type eq 'TOP10' ) {
            push $proxies->@*, '//37.58.52.41:4040?http&connect&socks';
        }
    }

    $cb->($proxies);

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
