package Pcore::API::Map::Field::Bool;

use Pcore qw[-class];

extends qw[Pcore::API::Map::Field];

has '+isa_type' => ( default => sub {Bool} );
has '+default_value' => ( isa => Bool );

around ext_model_field => sub {
    my $orig = shift;
    my $self = shift;

    my $field = $self->$orig(@_);

    $field->{type} = 'boolean';

    if ( $self->has_default_value ) {
        if ( defined $self->default_value ) {
            $field->{defaultValue} = $self->default_value ? $TRUE : $FALSE;
        }
        else {
            $field->{defaultValue} = undef;
        }
    }

    return $field;
};

no Pcore;

sub writer {
    my $self = shift;
    my $val  = shift;

    if ( defined $val && defined $val->$* ) {
        if ( $val->$* == 0 ) {
            $val = \$FALSE;
        }
        else {
            $val = \$TRUE;
        }
    }

    return $val;
}

1;
__END__
=pod

=encoding utf8

=cut
