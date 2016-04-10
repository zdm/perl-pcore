package Pcore::API::Response;

use Pcore -class;
use overload    #
  q[bool] => sub {
    return $_[0]->is_success;
  },
  q[0+] => sub {
    return $_[0]->status;
  },
  q[<=>] => sub {
    return !$_[2] ? $_[0]->status <=> $_[1] : $_[1] <=> $_[0]->status;
  },
  fallback => undef;

has status => ( is => 'ro', isa => PositiveInt, required => 1 );
has reason => ( is => 'lazy', isa => Str );

has is_success => ( is => 'lazy', isa => Bool, init_arg => undef );

sub _build_reason ($self) {
    if ( $self->is_success ) {
        return 'OK';
    }
    else {
        return 'Error';
    }
}

sub _build_is_success ($self) {
    return $self->status == 200 ? 1 : 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Response

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
