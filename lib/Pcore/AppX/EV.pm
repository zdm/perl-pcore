package Pcore::AppX::EV;

use Pcore qw[-class];

with qw[Pcore::AppX];

sub register {
    my $self = shift;

    return P->EV->register( $self->_check_ev(shift), @_ );
}

sub throw {
    my $self = shift;

    return P->EV->throw( $self->_check_ev(shift), @_ );
}

sub _check_ev {
    my $self = shift;
    my $ev   = shift;

    $ev = $self->app->name . q[#] . $ev unless P->EV->has_queue($ev);

    return $ev;
}

1;
__END__
=pod

=encoding utf8

=cut
