package Pcore::Core::EV::Object;

use Pcore qw[-class];
use overload    #
  q[""] => sub {
    return $_[0]->class;
  },
  q[cmp] => sub {
    return !$_[2] ? $_[0]->class cmp $_[1] : $_[1] cmp $_[0]->class;
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
