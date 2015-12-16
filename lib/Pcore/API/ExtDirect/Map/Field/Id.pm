package Pcore::API::Map::Field::Id;

use Pcore -class;

extends qw[Pcore::API::Map::Field::Int];

has '+name' => ( default => 'id', required => 0, init_arg => undef );

has '+persist' => ( default => 'rc', init_arg => undef );
has '+primary' => ( default => 1,    init_arg => undef );

has '+null' => ( default => 0, init_arg => undef );
has '+isa_type' => ( default => sub {PositiveInt}, init_arg => undef );    # manipulation with id = 0 isn't allowed
has '+default_value' => ( init_arg => undef );

has '+write_field' => ( default => 'always', init_arg => undef );
has '+depends' => ( init_arg => undef );

has '+filter_isa_type' => ( default => sub {PositiveOrZeroInt}, init_arg => undef );

around ext_model_field => sub {
    my $orig = shift;
    my $self = shift;

    return;
};

no Pcore;

1;
__END__
=pod

=encoding utf8

=cut
