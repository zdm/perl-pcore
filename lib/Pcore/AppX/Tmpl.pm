package Pcore::AppX::Tmpl;

use Pcore qw[-class];

with qw[Pcore::AppX];

has renderer => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Template'], default => sub { return P->tmpl }, init_arg => undef );

sub app_run {
    my $self = shift;

    $self->renderer;

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
