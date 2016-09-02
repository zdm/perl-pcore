package Pcore::App::API::Auth::Backend;

use Pcore -role;

requires qw[
  _build_host
  init
];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has host => ( is => 'lazy', isa => Str, init_arg => undef );
has is_connected => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Backend

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
