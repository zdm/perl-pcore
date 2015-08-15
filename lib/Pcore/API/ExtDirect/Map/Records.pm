package Pcore::API::Map::Records;

use Pcore qw[-class];
use Pcore::API::Map::Records::Record;

has call => ( is => 'ro', isa => InstanceOf ['Pcore::API::Map::Call'], required => 1, weak_ref => 1 );

has records => ( is => 'lazy', isa => ArrayRef [ InstanceOf ['Pcore::API::Map::Records::Record'] ], default => sub { [] }, init_arg => undef );
has id_index => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

has _iterator => ( is => 'rwp', isa => Int, default => 0, clearer => 1, init_arg => undef );

no Pcore;

# TODO
# call readers in dependecy order;
# implement check critical fields;
# cycle over api_map readable fields (persist, upload);
# if method use "id" field only - this is a special case;
# process id and client_id according to method setting;

sub add_in_records {
    my $self    = shift;
    my $recs    = shift;
    my $uploads = shift;

    my $client_id_index = {};
    my $method_fields   = $self->call->method->fields;
    my $fields_strict   = $self->call->method->fields_strict;

    for my $raw_rec ( $recs->@* ) {
        my $fields_strict_keys = $fields_strict ? { map { $_ => 1 } keys $raw_rec->%*, keys $uploads->%* } : {};

        # read fields
        my $readed_fields  = {};
        my $readed_uploads = {};

        for my $field_name ( keys $method_fields->%* ) {
            my $field = $method_fields->{$field_name};

            # mark field as allowed
            delete $fields_strict_keys->@{ $field_name, $field->alias_name };    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]

            my $val;

            # try to find field value in raw_rec or uploads by name or alias_name
            if ( $field->upload ) {
                if ( exists $uploads->{$field_name} ) {
                    $val = \$uploads->{$field_name};
                }
                elsif ( $uploads->{ $field->alias_name } ) {
                    $val = \$uploads->{ $field->alias_name };
                }
            }
            else {
                if ( exists $raw_rec->{$field_name} ) {
                    $val = \$raw_rec->{$field_name};
                }
                elsif ( exists $raw_rec->{ $field->alias_name } ) {
                    $val = \$raw_rec->{ $field->alias_name };
                }
            }

            # read field value
            try {
                $val = $field->_read_field( $val, $self->call );

                if ($val) {
                    if ( $field->upload ) {
                        $readed_uploads->{$field_name} = $val->$*;
                    }
                    else {
                        $readed_fields->{$field_name} = $val->$*;
                    }
                }
            }
            catch {
                my $e = shift;

                if ( !$e->propagated ) {
                    $e->propagate;
                }
                elsif ( $e->is_propagated('API::EXCEPTION') ) {
                    $self->call->_exception_data->{message} = qq[Field "$field_name" read error. ] . $self->call->_exception_data->{message};
                    $self->call->_exception_data->{errors}->{$field_name} = $self->call->_exception_data->{message};
                }
            };
        }

        # validate fields_strict condition
        $self->call->exception( q[Record has unrecognized fields: ] . join q[, ], map {qq["$_"]} keys $fields_strict_keys->%* ) if keys $fields_strict_keys->%*;

        if ( exists $readed_fields->{client_id} ) {
            $self->call->exception(qq[Can't process records with same client_id "$readed_fields->{client_id}" in single transaction ]) if exists $client_id_index->{ $readed_fields->{client_id} };

            $client_id_index->{ $readed_fields->{client_id} } = 1;
        }

        if ( exists $readed_fields->{id} && exists $self->id_index->{ $readed_fields->{id} } ) {
            $self->call->exception(qq[Can't process records with same id "$readed_fields->{id}" in single transaction ]);
        }

        # create record
        my $rec = Pcore::API::Map::Records::Record->new( { records => $self } );

        $rec->_set_in_record( $readed_fields, $readed_uploads );

        push $self->records, $rec;

        $self->id_index->{ $rec->id } = $rec if defined $rec->id;
    }

    return;
}

# READER
sub read_record {
    my $self = shift;

  REDO: if ( exists $self->records->[ $self->_iterator ] ) {
        my $rec = $self->records->[ $self->_iterator ];

        # increment iterator
        $self->_set__iterator( $self->_iterator + 1 );

        # call read_record hook
        my $hook_res = $self->call->method->call_hook( 'read_record', $rec );

        if ( defined $hook_res && $hook_res == -1 ) {    # skip read record, if hook return -1
            delete $self->id_index->{ $rec->id } if $rec->has_id;

            goto REDO;
        }

        return $rec;
    }

    return;
}

# return ids of indexed records
sub get_primary_keys {
    my $self = shift;

    return [ keys $self->id_index->%* ];
}

# WRITER
sub write_records {
    my $self     = shift;
    my $raw_recs = shift;

    my $writable_fields_names = $self->call->writable_fields;

    # no fields with readable permissions
    return [] if !$writable_fields_names;

    my $api_map_fields = $self->call->api_map->fields;

    my $res = [];

  RECORD: for my $raw_rec ( $raw_recs->@* ) {
        my $rec;

        if ( exists $raw_rec->{id} && exists $self->id_index->{ $raw_rec->{id} } ) {
            $rec = $self->id_index->{ $raw_rec->{id} };
        }
        else {
            $rec = Pcore::API::Map::Records::Record->new( { records => $self } );
        }

        my $writed_fields = {};

        my $writer = sub {
            my $field = shift;

            return 1 if exists $writed_fields->{ $field->name };

            $writed_fields->{ $field->name } = 1;

            # write all field dependecies first
            if ( $field->has_depends ) {
                for my $field_name ( $field->depends->@* ) {
                    return -1 if __SUB__->( $api_map_fields->{$field_name} ) == -1;
                }
            }

            # write field itself
            my $val = $field->_write_field( exists $raw_rec->{ $field->name } ? \$raw_rec->{ $field->name } : undef, $rec );

            if ($val) {
                if ( $val == -1 ) {    # skip record
                    return -1;
                }
                else {
                    $rec->set_out_field( $field->name, $val );
                }
            }

            return 1;
        };

        for my $field_name ( $writable_fields_names->@* ) {
            next RECORD if $writer->( $api_map_fields->{$field_name} ) == -1;
        }

        # call on_write_record hook
        my $hook_res = $self->call->method->call_hook( 'write_record', $rec );

        next RECORD if defined $hook_res && $hook_res == -1;    # skip write record, if hook return -1

        push $res, { $rec->out_fields->%{ grep { exists $rec->out_fields->{$_} } $writable_fields_names->@* } };
    }

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 22                   │ Subroutines::ProhibitExcessComplexity - Subroutine "add_in_records" with high complexity score (21)            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 32, 38, 91, 145      │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 84, 85               │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
