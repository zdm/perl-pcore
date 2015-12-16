package Pcore::API::Map::Field::Date;

use Pcore -class;

extends qw[Pcore::API::Map::Field];

has '+isa_type' => ( default => sub {Str} );

around ext_model_field => sub {
    my $orig = shift;
    my $self = shift;

    my $field = $self->$orig(@_);

    $field->{type} = 'date';

    $field->{dateFormat} = 'c';

    return $field;
};

no Pcore;

sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    return $val if !defined $val->$*;

    if ( my $date = P->date->parse( $val->$* ) ) {
        return $date;
    }
    else {
        return $call->exception(q[Invalid date format]);
    }
}

sub writer {
    my $self = shift;
    my $val  = shift;

    if ( defined $val && defined $val->$* ) {
        $val = P->date->from_string( $val->$* )->at_utc;
    }

    return $val;
}

1;
__END__
=pod

=encoding utf8

=cut
