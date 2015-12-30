package Pcore::API::Map::Param::Sort;

use Pcore -class;

extends qw[Pcore::API::Map::Param];

our $SORT_ISA = ArrayRef [ Dict [ property => Str, direction => Enum [ 'ASC', 'DESC' ] ] ];

has '+name' => ( is => 'ro', default => 'sort', init_arg => undef );
has '+null' => ( default => 0, init_arg => undef );
has '+isa_type'      => ( init_arg => undef );
has '+default_value' => ( isa      => ArrayRef );

around generate_api_map => sub {
    my $orig = shift;
    my $self = shift;

    my $api_map = $self->method->api_map;

    # check default value
    if ( $self->has_default_value ) {
        for my $sort ( $self->default_value->@* ) {
            if ( $sort =~ /\A[+-](.+)\z/sm ) {
                my $field_name = $1;

                die qq[Unknown sort field "$field_name"] if !exists $api_map->fields->{$field_name};

                die qq[Field "$field_name" isn't sortable] if !$api_map->fields->{$field_name}->sortable;
            }
            else {
                die q[Invalid sort order];
            }
        }
    }

    return $self->$orig;
};

sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    if ( !$is_default_value ) {
        $SORT_ISA->assert_valid( $val->$* );

        my $res = [];

        for my $sort ( $val->$*->@* ) {
            return $call->exception(qq[Unsortable field "$sort->{property}"]) if !exists $self->method->api_map->fields->{ $sort->{property} } || !$self->method->api_map->fields->{ $sort->{property} }->sortable;

            if ( $sort->{direction} eq 'ASC' ) {
                push $res, q[+] . $sort->{property};
            }
            else {
                push $res, q[-] . $sort->{property};
            }
        }

        return \$res;
    }
    else {
        return $val;
    }
}

1;
__END__
=pod

=encoding utf8

=cut
