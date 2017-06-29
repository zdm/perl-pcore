package Pcore::Handle::DBI;

use Pcore -role, -const, -result,
  -export => {
    ALL        => [qw[$TYPE_TO_ODBC]],
    ODBC_TYPES => [qw[$ODBC_UNKNOWN_TYPE $ODBC_INTEGER $ODBC_FLOAT $ODBC_VARCHAR $ODBC_BLOB]],
    TYPES      => [qw[$SQL_ABSTIME $SQL_ABSTIMEARRAY $SQL_ACLITEM $SQL_ACLITEMARRAY $SQL_ANY $SQL_ANYARRAY $SQL_ANYELEMENT $SQL_ANYENUM $SQL_ANYNONARRAY $SQL_ANYRANGE $SQL_BIT $SQL_BITARRAY $SQL_BOOL $SQL_BOOLARRAY $SQL_BOX $SQL_BOXARRAY $SQL_BPCHAR $SQL_BPCHARARRAY $SQL_BYTEA $SQL_BYTEAARRAY $SQL_CHAR $SQL_CHARARRAY $SQL_CID $SQL_CIDARRAY $SQL_CIDR $SQL_CIDRARRAY $SQL_CIRCLE $SQL_CIRCLEARRAY $SQL_CSTRING $SQL_CSTRINGARRAY $SQL_DATE $SQL_DATEARRAY $SQL_DATERANGE $SQL_DATERANGEARRAY $SQL_EVENT_TRIGGER $SQL_FDW_HANDLER $SQL_FLOAT4 $SQL_FLOAT4ARRAY $SQL_FLOAT8 $SQL_FLOAT8ARRAY $SQL_GTSVECTOR $SQL_GTSVECTORARRAY $SQL_INDEX_AM_HANDLER $SQL_INET $SQL_INETARRAY $SQL_INT2 $SQL_INT2ARRAY $SQL_INT2VECTOR $SQL_INT2VECTORARRAY $SQL_INT4 $SQL_INT4ARRAY $SQL_INT4RANGE $SQL_INT4RANGEARRAY $SQL_INT8 $SQL_INT8ARRAY $SQL_INT8RANGE $SQL_INT8RANGEARRAY $SQL_INTERNAL $SQL_INTERVAL $SQL_INTERVALARRAY $SQL_JSON $SQL_JSONARRAY $SQL_JSONB $SQL_JSONBARRAY $SQL_LANGUAGE_HANDLER $SQL_LINE $SQL_LINEARRAY $SQL_LSEG $SQL_LSEGARRAY $SQL_MACADDR $SQL_MACADDRARRAY $SQL_MONEY $SQL_MONEYARRAY $SQL_NAME $SQL_NAMEARRAY $SQL_NUMERIC $SQL_NUMERICARRAY $SQL_NUMRANGE $SQL_NUMRANGEARRAY $SQL_OID $SQL_OIDARRAY $SQL_OIDVECTOR $SQL_OIDVECTORARRAY $SQL_OPAQUE $SQL_PATH $SQL_PATHARRAY $SQL_PG_ATTRIBUTE $SQL_PG_CLASS $SQL_PG_DDL_COMMAND $SQL_PG_LSN $SQL_PG_LSNARRAY $SQL_PG_NODE_TREE $SQL_PG_PROC $SQL_PG_TYPE $SQL_POINT $SQL_POINTARRAY $SQL_POLYGON $SQL_POLYGONARRAY $SQL_RECORD $SQL_RECORDARRAY $SQL_REFCURSOR $SQL_REFCURSORARRAY $SQL_REGCLASS $SQL_REGCLASSARRAY $SQL_REGCONFIG $SQL_REGCONFIGARRAY $SQL_REGDICTIONARY $SQL_REGDICTIONARYARRAY $SQL_REGNAMESPACE $SQL_REGNAMESPACEARRAY $SQL_REGOPER $SQL_REGOPERARRAY $SQL_REGOPERATOR $SQL_REGOPERATORARRAY $SQL_REGPROC $SQL_REGPROCARRAY $SQL_REGPROCEDURE $SQL_REGPROCEDUREARRAY $SQL_REGROLE $SQL_REGROLEARRAY $SQL_REGTYPE $SQL_REGTYPEARRAY $SQL_RELTIME $SQL_RELTIMEARRAY $SQL_SMGR $SQL_TEXT $SQL_TEXTARRAY $SQL_TID $SQL_TIDARRAY $SQL_TIME $SQL_TIMEARRAY $SQL_TIMESTAMP $SQL_TIMESTAMPARRAY $SQL_TIMESTAMPTZ $SQL_TIMESTAMPTZARRAY $SQL_TIMETZ $SQL_TIMETZARRAY $SQL_TINTERVAL $SQL_TINTERVALARRAY $SQL_TRIGGER $SQL_TSM_HANDLER $SQL_TSQUERY $SQL_TSQUERYARRAY $SQL_TSRANGE $SQL_TSRANGEARRAY $SQL_TSTZRANGE $SQL_TSTZRANGEARRAY $SQL_TSVECTOR $SQL_TSVECTORARRAY $SQL_TXID_SNAPSHOT $SQL_TXID_SNAPSHOTARRAY $SQL_UNKNOWN $SQL_UUID $SQL_UUIDARRAY $SQL_VARBIT $SQL_VARBITARRAY $SQL_VARCHAR $SQL_VARCHARARRAY $SQL_VOID $SQL_XID $SQL_XIDARRAY $SQL_XML $SQL_XMLARRAY $SQL_BLOB]],
  };

use Pcore::Util::Scalar qw[is_ref is_plain_scalarref is_plain_hashref is_plain_arrayref is_plain_refref];
use Pcore::Handle::DBI::STH;

with qw[Pcore::Handle];

requires qw[_get_schema_patch_table_query prepare quote quote_id];

has on_connect => ( is => 'ro', isa => Maybe [CodeRef] );

has _schema_patch => ( is => 'ro', isa => HashRef, init_arg => undef );

const our $SCHEMA_PATCH_TABLE_NAME => '__schema_patch';

# POSTGRES TYPES
const our $SQL_ABSTIME            => 702;
const our $SQL_ABSTIMEARRAY       => 1023;
const our $SQL_ACLITEM            => 1033;
const our $SQL_ACLITEMARRAY       => 1034;
const our $SQL_ANY                => 2276;
const our $SQL_ANYARRAY           => 2277;
const our $SQL_ANYELEMENT         => 2283;
const our $SQL_ANYENUM            => 3500;
const our $SQL_ANYNONARRAY        => 2776;
const our $SQL_ANYRANGE           => 3831;
const our $SQL_BIT                => 1560;
const our $SQL_BITARRAY           => 1561;
const our $SQL_BOOL               => 16;
const our $SQL_BOOLARRAY          => 1000;
const our $SQL_BOX                => 603;
const our $SQL_BOXARRAY           => 1020;
const our $SQL_BPCHAR             => 1042;
const our $SQL_BPCHARARRAY        => 1014;
const our $SQL_BYTEA              => 17;
const our $SQL_BYTEAARRAY         => 1001;
const our $SQL_CHAR               => 18;
const our $SQL_CHARARRAY          => 1002;
const our $SQL_CID                => 29;
const our $SQL_CIDARRAY           => 1012;
const our $SQL_CIDR               => 650;
const our $SQL_CIDRARRAY          => 651;
const our $SQL_CIRCLE             => 718;
const our $SQL_CIRCLEARRAY        => 719;
const our $SQL_CSTRING            => 2275;
const our $SQL_CSTRINGARRAY       => 1263;
const our $SQL_DATE               => 1082;
const our $SQL_DATEARRAY          => 1182;
const our $SQL_DATERANGE          => 3912;
const our $SQL_DATERANGEARRAY     => 3913;
const our $SQL_EVENT_TRIGGER      => 3838;
const our $SQL_FDW_HANDLER        => 3115;
const our $SQL_FLOAT4             => 700;
const our $SQL_FLOAT4ARRAY        => 1021;
const our $SQL_FLOAT8             => 701;
const our $SQL_FLOAT8ARRAY        => 1022;
const our $SQL_GTSVECTOR          => 3642;
const our $SQL_GTSVECTORARRAY     => 3644;
const our $SQL_INDEX_AM_HANDLER   => 325;
const our $SQL_INET               => 869;
const our $SQL_INETARRAY          => 1041;
const our $SQL_INT2               => 21;
const our $SQL_INT2ARRAY          => 1005;
const our $SQL_INT2VECTOR         => 22;
const our $SQL_INT2VECTORARRAY    => 1006;
const our $SQL_INT4               => 23;
const our $SQL_INT4ARRAY          => 1007;
const our $SQL_INT4RANGE          => 3904;
const our $SQL_INT4RANGEARRAY     => 3905;
const our $SQL_INT8               => 20;
const our $SQL_INT8ARRAY          => 1016;
const our $SQL_INT8RANGE          => 3926;
const our $SQL_INT8RANGEARRAY     => 3927;
const our $SQL_INTERNAL           => 2281;
const our $SQL_INTERVAL           => 1186;
const our $SQL_INTERVALARRAY      => 1187;
const our $SQL_JSON               => 114;
const our $SQL_JSONARRAY          => 199;
const our $SQL_JSONB              => 3802;
const our $SQL_JSONBARRAY         => 3807;
const our $SQL_LANGUAGE_HANDLER   => 2280;
const our $SQL_LINE               => 628;
const our $SQL_LINEARRAY          => 629;
const our $SQL_LSEG               => 601;
const our $SQL_LSEGARRAY          => 1018;
const our $SQL_MACADDR            => 829;
const our $SQL_MACADDRARRAY       => 1040;
const our $SQL_MONEY              => 790;
const our $SQL_MONEYARRAY         => 791;
const our $SQL_NAME               => 19;
const our $SQL_NAMEARRAY          => 1003;
const our $SQL_NUMERIC            => 1700;
const our $SQL_NUMERICARRAY       => 1231;
const our $SQL_NUMRANGE           => 3906;
const our $SQL_NUMRANGEARRAY      => 3907;
const our $SQL_OID                => 26;
const our $SQL_OIDARRAY           => 1028;
const our $SQL_OIDVECTOR          => 30;
const our $SQL_OIDVECTORARRAY     => 1013;
const our $SQL_OPAQUE             => 2282;
const our $SQL_PATH               => 602;
const our $SQL_PATHARRAY          => 1019;
const our $SQL_PG_ATTRIBUTE       => 75;
const our $SQL_PG_CLASS           => 83;
const our $SQL_PG_DDL_COMMAND     => 32;
const our $SQL_PG_LSN             => 3220;
const our $SQL_PG_LSNARRAY        => 3221;
const our $SQL_PG_NODE_TREE       => 194;
const our $SQL_PG_PROC            => 81;
const our $SQL_PG_TYPE            => 71;
const our $SQL_POINT              => 600;
const our $SQL_POINTARRAY         => 1017;
const our $SQL_POLYGON            => 604;
const our $SQL_POLYGONARRAY       => 1027;
const our $SQL_RECORD             => 2249;
const our $SQL_RECORDARRAY        => 2287;
const our $SQL_REFCURSOR          => 1790;
const our $SQL_REFCURSORARRAY     => 2201;
const our $SQL_REGCLASS           => 2205;
const our $SQL_REGCLASSARRAY      => 2210;
const our $SQL_REGCONFIG          => 3734;
const our $SQL_REGCONFIGARRAY     => 3735;
const our $SQL_REGDICTIONARY      => 3769;
const our $SQL_REGDICTIONARYARRAY => 3770;
const our $SQL_REGNAMESPACE       => 4089;
const our $SQL_REGNAMESPACEARRAY  => 4090;
const our $SQL_REGOPER            => 2203;
const our $SQL_REGOPERARRAY       => 2208;
const our $SQL_REGOPERATOR        => 2204;
const our $SQL_REGOPERATORARRAY   => 2209;
const our $SQL_REGPROC            => 24;
const our $SQL_REGPROCARRAY       => 1008;
const our $SQL_REGPROCEDURE       => 2202;
const our $SQL_REGPROCEDUREARRAY  => 2207;
const our $SQL_REGROLE            => 4096;
const our $SQL_REGROLEARRAY       => 4097;
const our $SQL_REGTYPE            => 2206;
const our $SQL_REGTYPEARRAY       => 2211;
const our $SQL_RELTIME            => 703;
const our $SQL_RELTIMEARRAY       => 1024;
const our $SQL_SMGR               => 210;
const our $SQL_TEXT               => 25;
const our $SQL_TEXTARRAY          => 1009;
const our $SQL_TID                => 27;
const our $SQL_TIDARRAY           => 1010;
const our $SQL_TIME               => 1083;
const our $SQL_TIMEARRAY          => 1183;
const our $SQL_TIMESTAMP          => 1114;
const our $SQL_TIMESTAMPARRAY     => 1115;
const our $SQL_TIMESTAMPTZ        => 1184;
const our $SQL_TIMESTAMPTZARRAY   => 1185;
const our $SQL_TIMETZ             => 1266;
const our $SQL_TIMETZARRAY        => 1270;
const our $SQL_TINTERVAL          => 704;
const our $SQL_TINTERVALARRAY     => 1025;
const our $SQL_TRIGGER            => 2279;
const our $SQL_TSM_HANDLER        => 3310;
const our $SQL_TSQUERY            => 3615;
const our $SQL_TSQUERYARRAY       => 3645;
const our $SQL_TSRANGE            => 3908;
const our $SQL_TSRANGEARRAY       => 3909;
const our $SQL_TSTZRANGE          => 3910;
const our $SQL_TSTZRANGEARRAY     => 3911;
const our $SQL_TSVECTOR           => 3614;
const our $SQL_TSVECTORARRAY      => 3643;
const our $SQL_TXID_SNAPSHOT      => 2970;
const our $SQL_TXID_SNAPSHOTARRAY => 2949;
const our $SQL_UNKNOWN            => 705;
const our $SQL_UUID               => 2950;
const our $SQL_UUIDARRAY          => 2951;
const our $SQL_VARBIT             => 1562;
const our $SQL_VARBITARRAY        => 1563;
const our $SQL_VARCHAR            => 1043;
const our $SQL_VARCHARARRAY       => 1015;
const our $SQL_VOID               => 2278;
const our $SQL_XID                => 28;
const our $SQL_XIDARRAY           => 1011;
const our $SQL_XML                => 142;
const our $SQL_XMLARRAY           => 143;

# POSTGRES TYPES ALIASES
const our $SQL_BLOB => $SQL_BYTEA;

# DBI ODBC types
const our $ODBC_UNKNOWN_TYPE => 0;
const our $ODBC_INTEGER      => 4;
const our $ODBC_FLOAT        => 6;
const our $ODBC_VARCHAR      => 12;
const our $ODBC_BLOB         => 30;

# POSTGRES TYPE TO ODBC
const our $TYPE_TO_ODBC => {
    $SQL_BYTEA   => $ODBC_BLOB,
    $SQL_BOOL    => $ODBC_INTEGER,
    $SQL_FLOAT4  => $ODBC_FLOAT,
    $SQL_FLOAT8  => $ODBC_FLOAT,
    $SQL_INT2    => $ODBC_INTEGER,
    $SQL_INT4    => $ODBC_INTEGER,
    $SQL_INT8    => $ODBC_INTEGER,
    $SQL_MONEY   => $ODBC_FLOAT,
    $SQL_NUMERIC => $ODBC_FLOAT,
    $SQL_TEXT    => $ODBC_VARCHAR,
    $SQL_VARCHAR => $ODBC_VARCHAR,
    $SQL_CHAR    => $ODBC_VARCHAR,
    $SQL_UNKNOWN => $ODBC_UNKNOWN_TYPE,
};

# VALUES context:
# { aa => 1, bb => 2 },
# [ { aa => 1, bb => 2 }, { aa => 3, bb => 4 } ],
# [ [ 1, 2 ], [ 3, 4 ] ],
# [ \['col1', 'col2'], { aa => 1, col2 => 2 }, { aa => 3, bb => 4 } ],
# [ \['col1', 'col2', 'col3'], [ 1, 2 ], [ 3, 4, 5 ], [6] ],
sub prepare_query ( $self, $query ) {
    state $context_re = do {
        my @keywords = qw[SET VALUES WHERE];

        my $context_keywords_prepared = join q[|], sort { length $b <=> length $a } map {s/\s+/\\s+/smgr} @keywords;

        qr/(?:(?<=\A)|(?<=\s))(?:$context_keywords_prepared)(?=\s|\z)/smi;
    };

    my ( @sql, $bind, $i, $last_not_ref, $context );

    for my $arg ( $query->@* ) {
        if ( !is_ref $arg ) {
            die q[SQL query builder doesn't allow several consecutive non-ref argument] if $last_not_ref;

            $last_not_ref = 1;

            # trim
            push @sql, $arg =~ s/\A\s+|\s+\z//smgr;

            # analyse context
            if ( my $last_kw = ( $arg =~ /$context_re/smgi )[-1] ) {
                $context = uc $last_kw =~ s/\s+/ /smgr;
            }
        }
        else {
            $last_not_ref = 0;

            if ( is_plain_scalarref $arg) {
                push @sql, '$' . ++$i;

                push $bind->@*, $arg->$*;
            }
            else {

                # SET context
                if ( $context eq 'SET' ) {
                    my @fields;

                    for my $field ( sort keys $arg->%* ) {
                        push @fields, $self->quote_id($field) . ' = $' . ++$i;

                        push $bind->@*, $arg->{$field};
                    }

                    push @sql, join q[, ], @fields;
                }

                # WHERE context
                elsif ( $context eq 'WHERE' ) {
                    if ( is_plain_hashref $arg) {
                        my @fields;

                        for my $field ( keys $arg->%* ) {
                            push @fields, $self->quote_id($field) . ' = $' . ++$i;

                            push $bind->@*, $arg->{$field};
                        }

                        push @sql, '(' . join( ' AND ', @fields ) . ')';
                    }
                    elsif ( is_plain_arrayref $arg) {
                        push @sql, '(' . join( ', ', map { '$' . ++$i } $arg->@* ) . ')';

                        push $bind->@*, $arg->@*;
                    }
                    else {
                        die q[SQL "WHERE" context support only HashRef or ArrayReh arguments];
                    }
                }

                # VALUES context
                elsif ( $context eq 'VALUES' ) {
                    my ( $fields, $rows );

                    if ( is_plain_hashref $arg) {
                        $arg = [$arg];
                    }

                    my $is_first_row = 1;

                    for my $row ( $arg->@* ) {
                        if ($is_first_row) {
                            $is_first_row = 0;

                            # first argument is fields, must be \[]
                            if ( is_plain_refref $row ) {
                                $fields = $row->$*;

                                next;
                            }
                            elsif ( is_plain_hashref $row) {
                                $fields = [ sort keys $row->%* ];
                            }
                        }

                        if ( is_plain_hashref $row) {
                            die 'Fields names are not specified' if !defined $fields;

                            push $rows->@*, '(' . join( ', ', map { $self->quote( is_plain_arrayref $_ ? $_->@* : $_ ) } $row->@{ $fields->@* } ) . ')';
                        }

                        # TODO fill rest of columns with undef if number of columns is known
                        elsif ( is_plain_arrayref $row) {
                            push $rows->@*, '(' . join( ', ', map { $self->quote( is_plain_arrayref $_ ? $_->@* : $_ ) } $row->@* ) . ')';
                        }
                        else {
                            die 'Unsupported row format';
                        }
                    }

                    if ($fields) {
                        my $values_sql = '(' . join( ', ', map { $self->quote_id($_) } $fields->@* ) . ') VALUES';

                        $sql[-1] =~ s/VALUES.*\z/$values_sql/smi;
                    }

                    push @sql, join ', ', $rows->@*;
                }
                else {
                    die 'Unknown SQL context';
                }
            }
        }
    }

    return join( q[ ], @sql ), $bind;
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
                @_ = ( $self, $dbh, $cb );

                goto $self->can('_apply_patch');
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

                            # patch registered successfully
                            @_ = ( $self, $dbh, $cb );

                            goto $self->can('_apply_patch');
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
## |    3 | 221                  | Subroutines::ProhibitExcessComplexity - Subroutine "prepare_query" with high complexity score (29)             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 274, 303, 307, 317   | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 225                  | BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                |
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
