package Pcore::API::Map::Field::Int;

use Pcore -class;

extends qw[Pcore::API::Map::Field];

has '+isa_type' => ( default => sub {Int} );
has '+default_value' => ( isa => Int );

around ext_model_field => sub {
    my $orig = shift;
    my $self = shift;

    my $field = $self->$orig(@_);

    $field->{type} = 'int';

    return $field;
};

no Pcore;

sub writer {
    my $self = shift;
    my $val  = shift;

    if ( defined $val && defined $val->$* ) {
        $val->$* += 0;
    }

    return $val;
}

1;
__END__
=pod

=encoding utf8

=cut
