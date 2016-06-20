package Pcore::HTTP::Server::Router;

use Pcore -role;

use overload    #
  q[&{}] => sub ( $self, @ ) {
    return sub { return $self->run(@_) };
  },
  fallback => undef;

requires qw[run];

# TODO create request
around run => sub ( $orig, $self, $env ) {
    return $self->$orig($env);
};

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Router

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
