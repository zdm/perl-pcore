package Pcore::API::Map::Param::Filter;

use Pcore qw[-class];

extends qw[Pcore::API::Map::Param];

our $FILTER_ISA = ArrayRef [ Dict [ property => Str, value => Str, operator => Optional [ Enum [qw[< <= = > >= != in like]] ] ] ];

has '+name' => ( is => 'ro', default => 'filter', init_arg => undef );
has '+null' => ( default => 0, init_arg => undef );
has '+isa_type' => ( init_arg => undef );
has '+default_value' => ( isa => $FILTER_ISA, init_arg => undef );

no Pcore;

sub reader {
    my $self             = shift;
    my $val              = shift;
    my $call             = shift;
    my $is_default_value = shift;

    if ( !$is_default_value ) {
        $FILTER_ISA->assert_valid( $val->$* );

        my $res = {};

        for my $filter ( $val->$*->@* ) {
            my $field = $self->method->api_map->fields->{ $filter->{property} } // undef;

            return $call->exception(qq[Not filterable field "$filter->{property}"]) if !$field || !$field->filterable;

            # check value type constraint
            if ( $field->has_filter_isa_type ) {
                $field->filter_isa_type->assert_valid( $filter->{value} );
            }
            elsif ( $field->has_isa_type ) {
                $field->isa_type->assert_valid( $filter->{value} );
            }

            if ( $filter->{operator} eq 'in' ) {
                $res->{ $filter->{property} } = { -in => $filter->{value} };
            }
            elsif ( $filter->{operator} eq 'like' ) {
                $res->{ $filter->{property} } = { -like => $filter->{value} };
            }
            else {
                $res->{ $filter->{property} } = { $filter->{operator}, $filter->{value} };
            }
        }

        return \$res;
    }
    else {
        return $val;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 28                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
