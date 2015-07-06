package Pcore::API::Map::Method::Destroy;

use Pcore qw[-class];

extends qw[Pcore::API::Map::Method];

has '+use_fields' => ( default => 'id', init_arg => undef );

no Pcore;

1;
__END__
=pod

=encoding utf8

=cut
