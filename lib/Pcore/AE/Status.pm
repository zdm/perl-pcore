package Pcore::AE::Status;

use Pcore -role;

has _on_status => ( is => 'ro', isa => CodeRef, predicate => 1, init_arg => 'on_status' );

has status => ( is => 'ro', isa => Str, writer => '__set_status', init_arg => undef );

no Pcore;

sub _set_status {
    my $self   = shift;
    my $status = shift;

    my $old_status = $self->status;

    return if defined $old_status && $status eq $old_status;

    if ( $self->before_set_status( $status, $old_status ) ) {
        $self->__set_status($status);

        $self->on_status( $status, $old_status );

        $self->_on_status->( $self, $status, $old_status ) if $self->_has_on_status;
    }

    return;
}

# can be redefined in subclass
sub before_set_status {
    my $self       = shift;
    my $status     = shift;
    my $old_status = shift;

    return 1;
}

# can be redefined in subclass
sub on_status {
    my $self       = shift;
    my $status     = shift;
    my $old_status = shift;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 11                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_set_status' declared but not used  │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
