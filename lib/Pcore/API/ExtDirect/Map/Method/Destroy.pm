package Pcore::API::Map::Method::Destroy;

use Pcore -class;

extends qw[Pcore::API::Map::Method];

has '+use_fields' => ( default => 'id', init_arg => undef );

1;
__END__
=pod

=encoding utf8

=cut
