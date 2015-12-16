package Pcore::API::Class::Grid;

use Pcore -role;

with qw[Pcore::API::Class];

requires qw[_build_dbh_name _build_table];

has table    => ( is => 'lazy', isa => Str, init_arg => undef );
has dbh_name => ( is => 'lazy', isa => Str, init_arg => undef );

has dbh => ( is => 'lazy', isa => ConsumerOf ['Pcore::DBD'], init_arg => undef, weak_ref => 1 );

our $RESERVED_FIELDS_NAMES = [qw[]];

our $FIELDS = {
    id        => { type => 'id' },
    client_id => { type => 'client_id' },
};

our $METHODS = {
    create => { type => 'create' },
    read   => {
        type   => 'read',
        params => [         #
            { type => 'id' },
            { type => 'fields' },
            { type => 'filter' },
            { type => 'limit', default_value => 25, max_value => 50 },
            { type => 'start' },
            { type => 'sort' },
        ],
        public => 1,
    },
    update  => { type => 'update' },
    destroy => { type => 'destroy' },
};

around BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig(@_);

    $self->add_reserved_fields_names($RESERVED_FIELDS_NAMES);

    $self->add_fields($FIELDS);

    $self->add_methods($METHODS);

    return;
};

# DDL
around APP_BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig;

    my $sql = q[
        CREATE TABLE IF NOT EXISTS ] . $self->dbh->quote_id( $self->table ) . q[ (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            PRIMARY KEY (`id`)
        ) ENGINE = InnoDB;
    ];

    $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES]] );

    return;
};

sub run_ddl {
    my $self     = shift;
    my $sql      = shift;
    my $sql_mode = shift;

    return $self->dbh->ddl( { ddl => $sql, id => $self->ext_class_ns, sql_mode => $sql_mode } )->run;
}

no Pcore;

sub _build_dbh {
    my $self = shift;

    my $dbh_name = $self->dbh_name;

    return $self->h_cache->$dbh_name;
}

# API CREATE
sub api_create {
    my $self    = shift;
    my $records = shift;
    my $call    = shift;

    my $recs;

    try {
        $self->dbh->begin_work;

        # iterate over records
        while ( my $rec = $records->read_record ) {
            $self->dbh->query( 'INSERT INTO', \$self->table, 'VALUES', $rec->in_fields )->do;

            # update record id
            $rec->set_id( $self->dbh->last_insert_id );
        }

        $self->dbh->commit;

        # read all inserted records
        $recs = $self->dbh->query( 'SELECT', $call->persist_fields, 'FROM', \$self->table, 'WHERE id IN', $records->get_primary_keys )->selectall;
    }
    catch {
        my $e = shift;

        $self->dbh->rollback;

        $e->propagate;
    };

    return $recs;
}

# API READ
sub api_read {
    my $self   = shift;
    my $params = shift;
    my $call   = shift;

    if ( exists $params->{id} ) {
        return $self->dbh->query( 'SELECT * FROM', \$self->table, 'WHERE id = ', \$params->{id}->value )->selectall;
    }
    else {
        my $query = $self->dbh->query(    #
            'SELECT', $call->persist_fields,
            'FROM',   \$self->table,
            ( exists $params->{filter} ? ( 'WHERE',    $params->{filter}->value ) : () ),
            ( exists $params->{order}  ? ( 'ORDER BY', $params->{sort}->value )   : () ),
            ( exists $params->{limit} || exists $params->{start} ? ( 'LIMIT', [ $params->{limit}->value, $params->{start}->value ] ) : () ),
        );

        if ( exists $params->{limit} ) {    # total calculated only if limit param used
            if ( my $total = $self->db_get_total($params)->$* ) {
                return $query->selectall, total => $total;
            }
            else {
                return;
            }
        }
        else {
            return $query->selectall;
        }
    }
}

# API UPDATE
sub api_update {
    my $self    = shift;
    my $records = shift;
    my $call    = shift;

    my $recs;

    try {
        $self->dbh->begin_work;

        # iterate over records
        while ( my $rec = $records->read_record ) {
            $self->dbh->query( 'UPDATE', \$self->table, 'SET', $rec->in_fields, 'WHERE id =', \$rec->id )->do;
        }

        $self->dbh->commit;

        # read all updated records
        $recs = $self->dbh->query( 'SELECT', $call->persist_fields, 'FROM', \$self->table, 'WHERE id IN', $records->get_primary_keys )->selectall;
    }
    catch {
        my $e = shift;

        $self->dbh->rollback;

        $e->propagate;
    };

    return $recs;
}

# API DESTROY
sub api_destroy {
    my $self    = shift;
    my $records = shift;
    my $call    = shift;

    my $recs;

    try {
        $self->dbh->begin_work;

        # iterate over records
        while ( my $rec = $records->read_record ) {
            push $recs->@*, { id => $rec->id };
        }

        # prepare delete query and delete all in one query
        $self->dbh->query( 'DELETE FROM', \$self->table, 'WHERE id IN', $records->get_primary_keys )->do;

        $self->dbh->commit;
    }
    catch {
        my $e = shift;

        $self->dbh->rollback;

        $e->propagate;
    };

    return $recs;
}

# DBH METHODS
sub db_get_total {
    my $self   = shift;
    my $params = shift;

    return $self->dbh->query( 'SELECT COUNT(*) FROM', \$self->table, ( exists $params->{filter} ? ( 'WHERE', $params->{filter}->value ) : () ) )->selectval;
}

# EXT PANEL
sub ext_class_panel {
    my $self = shift;

    return $self->ext_define(
        'Ext.panel.Panel',
        {   controller => { type => $self->ext_type('Pcore.grid.ViewController') },
            viewModel  => {
                stores => {    #
                    store => $self->ext_class_store,
                },
                data => {
                    editModel      => undef,
                    selectedRecord => undef,
                },
            },

            createFormPanelClass => $self->ext_class('FormPanel'),
            updateFormPanelClass => $self->ext_class('FormPanel'),

            layout => 'card',
            items  => $self->ext_class_grid_panel->apply(
                {   itemId    => 'grid',
                    listeners => { rowDblClick => 'onRecordDblClick', },
                }
            ),
        }
    );
}

# EXT STORE
sub ext_class_store {
    my $self = shift;

    return $self->ext_define(
        'Ext.data.Store',
        {   autoLoad     => $TRUE,
            pageSize     => 25,
            remoteSort   => $TRUE,
            remoteFilter => $TRUE,
            model        => $self->ext_class( 'Model', require => 1 ),
        },
    );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 61, 62               │ ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
