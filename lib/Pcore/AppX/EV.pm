package Pcore::AppX::EV;

use Pcore qw[-class];

with qw[Pcore::AppX];

sub register ( $self, $name, @args ) {
    return P->EV->register( $self->_check_ev($name), @args );
}

sub throw ( $self, $name, @args ) {
    return P->EV->throw( $self->_check_ev($name), @args );
}

sub _check_ev ( $self, $name ) {
    if ( P->EV->has_queue($name) ) {
        return $name;
    }
    else {
        return $self->app->name . q[#] . $name;
    }
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AppX::EV

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
