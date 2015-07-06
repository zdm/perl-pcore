package Pcore::API::Map::Records::Record;

use Pcore qw[-class];

has records => ( is => 'ro', isa => InstanceOf ['Pcore::API::Map::Records'], required => 1, weak_ref => 1 );

has id        => ( is => 'rwp', isa => Int,         predicate => 1, init_arg => undef );
has client_id => ( is => 'rwp', isa => NegativeInt, predicate => 1, init_arg => undef );

has in_fields => ( is => 'rwp', isa => HashRef, predicate => 1, init_arg => undef );    # persist fields, excluding uploads, id, client_id
has uploads   => ( is => 'rwp', isa => HashRef, predicate => 1, init_arg => undef );    # upload fields

has orig_fields => ( is => 'rwp', isa => HashRef, predicate => 1, init_arg => undef );
has out_fields => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

sub _set_in_record {
    my $self    = shift;
    my $fields  = shift;
    my $uploads = shift;

    $self->_set_id( delete $fields->{id} ) if exists $fields->{id};

    $self->_set_client_id( delete $fields->{client_id} ) if exists $fields->{client_id};

    $self->_set_in_fields($fields);

    $self->_set_uploads($uploads);

    return;
}

sub set_id {
    my $self = shift;
    my $id   = shift;

    $self->_set_id($id);

    $self->records->id_index->{$id} = $self;

    return;
}

sub set_orig_record {
    my $self = shift;
    my $rec  = shift;

    $self->_set_orig_fields($rec);

    return;
}

sub set_out_field {
    my $self       = shift;
    my $field_name = shift;
    my $val        = shift;

    $self->out_fields->{$field_name} = $val->$*;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 18                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_set_in_record' declared but not    │
## │      │                      │ used                                                                                                           │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
