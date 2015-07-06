package Pcore::API::Map::Method::Create;

use Pcore qw[-class];

extends qw[Pcore::API::Map::Method];

has '+use_fields' => ( default => 'all', init_arg => undef );
has '+read_client_id'         => ( default => 1 );
has '+write_client_id'        => ( default => 1 );
has '+check_critical_fields'  => ( default => 1 );
has '+read_persist_rc_fields' => ( default => 1 );

no Pcore;

1;
__END__
=pod

=encoding utf8

=cut
