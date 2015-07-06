package Pcore::API::Map::Param::Limit;

use Pcore qw[-class];

extends qw[Pcore::API::Map::Param];

has '+name' => ( is => 'ro', default => 'limit', init_arg => undef );
has '+null' => ( default => 0, init_arg => undef );
has '+isa_type' => ( default => sub {PositiveInt}, init_arg => undef );
has '+default_value' => ( isa => PositiveInt, default => 25 );

has max_value => ( is => 'ro', isa => PositiveInt, default => 50 );

no Pcore;

sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    return $call->exception( q[Max. allowed limit value is ] . $self->max_value ) if $self->max_value && $val->$* > $self->max_value;

    return $val;
}

1;
__END__
=pod

=encoding utf8

=cut
