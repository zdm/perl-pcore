package Pcore::Handle::DBI;

use Pcore -role, -const, -result, -export => { TYPES => [qw[$SQL_ALL_TYPES $SQL_ARRAY $SQL_ARRAY_LOCATOR $SQL_BIGINT $SQL_BINARY $SQL_BIT $SQL_BLOB $SQL_BLOB_LOCATOR $SQL_BOOLEAN $SQL_CHAR $SQL_CLOB $SQL_CLOB_LOCATOR $SQL_DATE $SQL_DATETIME $SQL_DECIMAL $SQL_DOUBLE $SQL_FLOAT $SQL_GUID $SQL_INTEGER $SQL_INTERVAL $SQL_INTERVAL_DAY $SQL_INTERVAL_DAY_TO_HOUR $SQL_INTERVAL_DAY_TO_MINUTE $SQL_INTERVAL_DAY_TO_SECOND $SQL_INTERVAL_HOUR $SQL_INTERVAL_HOUR_TO_MINUTE $SQL_INTERVAL_HOUR_TO_SECOND $SQL_INTERVAL_MINUTE $SQL_INTERVAL_MINUTE_TO_SECOND $SQL_INTERVAL_MONTH $SQL_INTERVAL_SECOND $SQL_INTERVAL_YEAR $SQL_INTERVAL_YEAR_TO_MONTH $SQL_LONGVARBINARY $SQL_LONGVARCHAR $SQL_MULTISET $SQL_MULTISET_LOCATOR $SQL_NUMERIC $SQL_REAL $SQL_REF $SQL_ROW $SQL_SMALLINT $SQL_TIME $SQL_TIMESTAMP $SQL_TINYINT $SQL_TYPE_DATE $SQL_TYPE_TIME $SQL_TYPE_TIMESTAMP $SQL_TYPE_TIMESTAMP_WITH_TIMEZONE $SQL_TYPE_TIME_WITH_TIMEZONE $SQL_UDT $SQL_UDT_LOCATOR $SQL_UNKNOWN_TYPE $SQL_VARBINARY $SQL_VARCHAR $SQL_WCHAR $SQL_WLONGVARCHAR $SQL_WVARCHAR]], };
use Pcore::Util::Scalar qw[is_ref is_plain_scalarref is_plain_hashref is_plain_arrayref];

with qw[Pcore::Handle];

requires qw[_get_schema_patch_table_query quote_id];

has on_connect => ( is => 'ro', isa => Maybe [CodeRef] );

has _schema_patch => ( is => 'ro', isa => HashRef, init_arg => undef );

const our $SCHEMA_PATCH_TABLE_NAME => '__schema_patch';

const our $SQL_ALL_TYPES                    => 0;
const our $SQL_ARRAY                        => 50;
const our $SQL_ARRAY_LOCATOR                => 51;
const our $SQL_BIGINT                       => -5;
const our $SQL_BINARY                       => -2;
const our $SQL_BIT                          => -7;
const our $SQL_BLOB                         => 30;
const our $SQL_BLOB_LOCATOR                 => 31;
const our $SQL_BOOLEAN                      => 16;
const our $SQL_CHAR                         => 1;
const our $SQL_CLOB                         => 40;
const our $SQL_CLOB_LOCATOR                 => 41;
const our $SQL_DATE                         => 9;
const our $SQL_DATETIME                     => 9;
const our $SQL_DECIMAL                      => 3;
const our $SQL_DOUBLE                       => 8;
const our $SQL_FLOAT                        => 6;
const our $SQL_GUID                         => -11;
const our $SQL_INTEGER                      => 4;
const our $SQL_INTERVAL                     => 10;
const our $SQL_INTERVAL_DAY                 => 103;
const our $SQL_INTERVAL_DAY_TO_HOUR         => 108;
const our $SQL_INTERVAL_DAY_TO_MINUTE       => 109;
const our $SQL_INTERVAL_DAY_TO_SECOND       => 110;
const our $SQL_INTERVAL_HOUR                => 104;
const our $SQL_INTERVAL_HOUR_TO_MINUTE      => 111;
const our $SQL_INTERVAL_HOUR_TO_SECOND      => 112;
const our $SQL_INTERVAL_MINUTE              => 105;
const our $SQL_INTERVAL_MINUTE_TO_SECOND    => 113;
const our $SQL_INTERVAL_MONTH               => 102;
const our $SQL_INTERVAL_SECOND              => 106;
const our $SQL_INTERVAL_YEAR                => 101;
const our $SQL_INTERVAL_YEAR_TO_MONTH       => 107;
const our $SQL_LONGVARBINARY                => -4;
const our $SQL_LONGVARCHAR                  => -1;
const our $SQL_MULTISET                     => 55;
const our $SQL_MULTISET_LOCATOR             => 56;
const our $SQL_NUMERIC                      => 2;
const our $SQL_REAL                         => 7;
const our $SQL_REF                          => 20;
const our $SQL_ROW                          => 19;
const our $SQL_SMALLINT                     => 5;
const our $SQL_TIME                         => 10;
const our $SQL_TIMESTAMP                    => 11;
const our $SQL_TINYINT                      => -6;
const our $SQL_TYPE_DATE                    => 91;
const our $SQL_TYPE_TIME                    => 92;
const our $SQL_TYPE_TIMESTAMP               => 93;
const our $SQL_TYPE_TIMESTAMP_WITH_TIMEZONE => 95;
const our $SQL_TYPE_TIME_WITH_TIMEZONE      => 94;
const our $SQL_UDT                          => 17;
const our $SQL_UDT_LOCATOR                  => 18;
const our $SQL_UNKNOWN_TYPE                 => 0;
const our $SQL_VARBINARY                    => -3;
const our $SQL_VARCHAR                      => 12;
const our $SQL_WCHAR                        => -8;
const our $SQL_WLONGVARCHAR                 => -10;
const our $SQL_WVARCHAR                     => -9;

# TODO "VALUES" context
sub prepare_query ( $self, $query ) {
    state $context_re = do {
        my @keywords = qw[SET VALUES WHERE];

        my $context_keywords_prepared = join q[|], sort { length $b <=> length $a } map {s/\s+/\\s+/smgr} @keywords;

        qr/(?:(?<=\A)|(?<=\s))(?:$context_keywords_prepared)(?=\s|\z)/smi;
    };

    my ( $sql, $bind, $i, $last_not_ref, $context );

    for my $arg ( $query->@* ) {
        if ( !is_ref $arg ) {
            die q[SQL query builder doesn't allow several consecutive non-ref argument] if $last_not_ref;

            $last_not_ref = 1;

            # trim
            $sql .= ' ' . $arg =~ s/\A\s+|\s+\z//smgr;

            # analyse context
            if ( my $last_kw = ( $arg =~ /$context_re/smgi )[-1] ) {
                $context = uc $last_kw =~ s/\s+/ /smgr;
            }
        }
        else {
            $last_not_ref = 0;

            if ( is_plain_scalarref $arg) {
                $sql .= ' $' . ++$i;

                push $bind->@*, $arg->$*;
            }
            else {
                if ( $context eq 'SET' ) {
                    my @fields;

                    for my $field ( sort keys $arg->%* ) {
                        push @fields, $self->quote_id($field) . ' = $' . ++$i;

                        push $bind->@*, $arg->{$field};
                    }

                    $sql .= ' ' . join q[, ], @fields;
                }
                elsif ( $context eq 'WHERE' ) {
                    if ( is_plain_hashref $arg) {
                        my @fields;

                        for my $field ( keys $arg->%* ) {
                            push @fields, $self->quote_id($field) . ' = $' . ++$i;

                            push $bind->@*, $arg->{$field};
                        }

                        $sql .= ' (' . join( ' AND ', @fields ) . ')';
                    }
                    elsif ( is_plain_arrayref $arg) {
                        $sql .= ' (' . join( ', ', map { '$' . ++$i } $arg->@* ) . ')';

                        push $bind->@*, $arg->@*;
                    }
                    else {
                        die q[SQL "WHERE" context support only HashRef or ArrayReh arguments];
                    }
                }
                elsif ( $context eq 'VALUES' ) {

                    # TODO
                }
                else {
                    die 'Unknown SQL context';
                }
            }
        }
    }

    return $sql, $bind;
}

# SCHEMA PATCH
sub add_schema_patch ( $self, $id, $query ) {
    die qq[Schema patch id "$id" already exists] if exists $self->{_schema_patch}->{$id};

    $self->{_schema_patch}->{$id} = {
        id    => $id,
        query => $query,
    };

    return;
}

sub upgrade_schema ( $self, $cb ) {
    my $on_finish = sub ( $status, $dbh ) {
        delete $self->{_schema_patch};

        if ($status) {
            $dbh->commit(
                sub ( $status, $dbh ) {
                    $cb->($status);

                    return;
                }
            );
        }
        else {
            if ( !$dbh ) {
                $cb->($status);
            }
            else {
                $dbh->rollback(
                    sub ( $status1, $dbh ) {
                        $cb->($status);

                        return;
                    }
                );
            }
        }

        return;
    };

    # start transaction
    $self->begin_work(
        sub ( $status, $dbh ) {
            return $on_finish->( $status, $dbh ) if !$status;

            # create patch table
            $dbh->do(
                $self->_get_schema_patch_table_query($SCHEMA_PATCH_TABLE_NAME),
                sub ( $status, $dbh, $data ) {
                    return $on_finish->( $status, $dbh ) if !$status;

                    $self->_apply_patch(
                        $dbh,
                        sub ($status) {
                            return $on_finish->( $status, $dbh );
                        }
                    );
                }
            );

            return;
        }
    );

    return;
}

sub _apply_patch ( $self, $dbh, $cb ) {
    return $cb->( result 200 ) if !$self->{_schema_patch}->%*;

    my $id = ( sort keys $self->{_schema_patch}->%* )[0];

    my $patch = delete $self->{_schema_patch}->{$id};

    $dbh->selectrow(
        qq[SELECT "id" FROM "$SCHEMA_PATCH_TABLE_NAME" WHERE "id" = \$1],
        [ $patch->{id} ],
        sub ( $status, $dbh, $data ) {
            return $cb->($status) if !$status;

            # patch is already exists
            if ($data) {
                AE::postpone { $self->_apply_patch( $dbh, $cb ) };

                return;
            }

            # apply patch
            $dbh->do(
                $patch->{query},
                sub ( $status, $dbh, $data ) {
                    return $cb->( result [ 500, qq[Failed to apply schema patch "$id": $status->{reason}] ] ) if !$status;

                    # register patch
                    $dbh->do(
                        qq[INSERT INTO "$SCHEMA_PATCH_TABLE_NAME" ("id") VALUES (\$1)],
                        [ $patch->{id} ],
                        sub ( $status, $dbh, $data ) {
                            return $cb->( result [ 500, qq[Failed to register patch "$id": $status->{reason}] ] ) if !$status;

                            AE::postpone { $self->_apply_patch( $dbh, $cb ) };

                            return;
                        }
                    );
                }
            );

            return;
        }
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 125                  | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 94, 119              | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 80                   | BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Handle::DBI

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
