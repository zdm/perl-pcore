package Pcore::API::Map::Field::ClientId;

use Pcore -class;

extends qw[Pcore::API::Map::Field::Int];

has '+name' => ( default => 'client_id', required => 0, init_arg => undef );

has '+persist' => ( init_arg => undef );

has '+null' => ( default => 0, init_arg => undef );
has '+isa_type' => ( default => sub {NegativeInt}, init_arg => undef );
has '+default_value' => ( init_arg => undef );

has '+write_field' => ( default => 'never', init_arg => undef );
has '+depends' => ( init_arg => undef );

has '+writer_method' => ( default => undef, init_arg => undef );

around ext_model_field => sub {
    my $orig = shift;
    my $self = shift;

    return;
};

sub _write_field {
    my $self = shift;
    my $val  = shift;
    my $rec  = shift;

    if ( $rec->has_in_fields ) {
        if ( $rec->has_client_id ) {
            $val = \$rec->client_id;
        }
        elsif ( $rec->has_id ) {
            $val = \$rec->id;
        }
    }

    return -1 unless $val;    # skip record

    return $self->writer($val);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 27                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_write_field' declared but not used │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
