package Pcore::API::Map::Method::Update;

use Pcore -class;

extends qw[Pcore::API::Map::Method];

has '+use_fields' => ( default => 'all', init_arg => undef );
has '+write_client_id' => ( default => 1 );

no Pcore;

1;
__END__
=pod

=encoding utf8

=cut
