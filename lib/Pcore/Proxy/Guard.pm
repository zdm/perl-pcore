package Pcore::Proxy::Guard;

use Pcore qw[-class -autoload];

has _guard_proxy => ( is => 'ro', required => 1 );

no Pcore;

sub DEMOLISH ( $self, $global ) {
    $self->_guard_proxy->_source->_finish_thread( $self->_guard_proxy ) if !$global;

    return;
}

sub autoload ( $self, $method, @ ) {
    return sub {
        my $self = shift;

        return $self->_guard_proxy->$method(@_);
    };
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 10                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy::Guard

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
