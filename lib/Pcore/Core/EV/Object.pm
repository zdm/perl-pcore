package Pcore::Core::EV::Object;

use Pcore qw[-class];
use overload    #
  q[""] => sub {
    my $self = shift;

    return $self->class;
  },
  q[cmp] => sub {
    my $self = shift;
    my $str  = shift;

    return $self->class cmp $str;
  },
  fallback => undef;

has class           => ( is => 'ro', isa => Str,  required => 1 );
has _stop_propagate => ( is => 'rw', isa => Bool, default  => 0, init_arg => undef );
has _remove         => ( is => 'rw', isa => Bool, default  => 0, init_arg => undef );

sub stop_propagate {
    my $self = shift;

    return $self->_stop_propagate(1);
}

sub remove {
    my $self = shift;

    return $self->_remove(1);
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::EV::Object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
