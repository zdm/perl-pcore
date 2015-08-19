package Pcore::AnyEvent::Proxy::Source::List;

use Pcore qw[-class];

with qw[Pcore::AnyEvent::Proxy::Source];

has proxies => ( is => 'ro', isa => ArrayRef [Str], required => 1 );

no Pcore;

sub load {
    my $self    = shift;
    my $cv      = shift;
    my $proxies = shift;

    $cv->begin;

    for ( $self->proxies->@* ) {
        push $proxies, { addr => $_ };
    }

    $cv->end;

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
