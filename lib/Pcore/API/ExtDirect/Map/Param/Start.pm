package Pcore::API::Map::Param::Start;

use Pcore qw[-class];

extends qw[Pcore::API::Map::Param];

has '+name' => ( is => 'ro', default => 'start', init_arg => undef );
has '+null' => ( default => 0, init_arg => undef );
has '+isa_type' => ( default => sub {PositiveOrZeroInt}, init_arg => undef );
has '+default_value' => ( isa => PositiveOrZeroInt, default => 0 );

no Pcore;

1;
__END__
=pod

=encoding utf8

=cut
