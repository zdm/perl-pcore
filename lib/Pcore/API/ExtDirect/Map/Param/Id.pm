package Pcore::API::Map::Param::Id;

use Pcore -class;

extends qw[Pcore::API::Map::Param];

has '+name' => ( is => 'ro', default => 'id', init_arg => undef );
has '+null' => ( default => 0, init_arg => undef );
has '+isa_type' => ( default => sub {PositiveOrZeroInt}, init_arg => undef );
has '+default_value' => ( init_arg => undef );

around generate_api_map => sub {
    my $orig = shift;
    my $self = shift;

    die q[Filter requires "id" field to be declared] unless exists $self->method->api_map->fields->{id};

    return $self->$orig;
};

no Pcore;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 16                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
