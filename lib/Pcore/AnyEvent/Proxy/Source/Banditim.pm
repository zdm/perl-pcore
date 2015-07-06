package Pcore::AnyEvent::Proxy::Source::Banditim;

use Pcore qw[-class];

with qw[Pcore::AnyEvent::Proxy::Source];

has type => ( is => 'ro', isa => Enum [qw[ANY FASTEST TOP10]], default => 'FASTEST' );    # TOP10 - top 10% of all proxies

has '+max_threads' => ( isa => Enum [ 50, 100, 200 ], default => 50 );
has '+is_multiproxy' => ( default => 1 );

no Pcore;

sub load {
    my $self    = shift;
    my $cv      = shift;
    my $proxies = shift;

    $cv->begin;

    if ( $self->type eq 'ANY' ) {
        push $proxies, { addr => '37.58.52.41:2020', http => 1, https => 1, socks => 1 };
    }
    elsif ( $self->type eq 'FASTEST' ) {
        push $proxies, { addr => '37.58.52.41:3030', http => 1, https => 1, socks => 1 };
    }
    elsif ( $self->type eq 'TOP10' ) {
        push $proxies, { addr => '37.58.52.41:4040', http => 1, https => 1, socks => 1 };
    }

    $cv->end;

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
