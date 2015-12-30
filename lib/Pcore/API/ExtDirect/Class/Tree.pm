package Pcore::API::Class::Tree;

use Pcore -role;

with qw[Pcore::API::Class::Grid];

has path_table => ( is => 'lazy', isa => Str );

our $RESERVED_FIELDS_NAMES = [qw[data expandable cls icon_cls icon root is_last is_first allow_drop allow_drag loading href tref_target]];

our $FIELDS = {

    # system fields
    parent_id => { type => 'int', persist => 'rw', isa_type => PositiveOrZeroInt },
    index     => { type => 'int', persist => 'rw', isa_type => PositiveOrZeroInt, default_value => 0 },
    text  => { type => 'str', persist => 'rw' },
    depth => { type => 'int', persist => 'ro', depends => ['parent_id'] },

    # system non-persist fields
    leaf     => { type => 'bool', default_value => 0 },
    loaded   => { type => 'bool', default_value => 1 },
    qtip     => { type => 'str',  default_value => q[] },
    qtitle   => { type => 'str',  default_value => q[] },
    checked  => { type => 'bool', null          => 1, default_value => undef },    # this field should be overridden to be persistent if the tree is using the checkbox feature
    expanded => { type => 'bool', default_value => 0 },                            # used to store the expanded/collapsed state of a node

    # custom fields
    desc    => { type => 'str',  persist => 'rw', blank         => 1 },
    created => { type => 'date', persist => 'ro', default_value => undef },
};

our $METHODS = {
    create => { type => 'create' },
    read   => {
        type   => 'read',
        params => [                                                                #
            { type => 'id',        critical => 1, },
            { name => 'min_depth', isa_type => PositiveOrZeroInt, null => 0, default_value => 0, },
            { name => 'max_depth', isa_type => PositiveOrZeroInt, null => 0, default_value => 0, },
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

    {
        my $sql = q[
        ALTER TABLE ] . $self->dbh->quote_id( $self->table ) . q[
            ADD COLUMN IF NOT EXISTS `parent_id` BIGINT UNSIGNED NOT NULL,
            ADD COLUMN IF NOT EXISTS `depth` INT UNSIGNED NOT NULL,
            ADD COLUMN IF NOT EXISTS `index` INT UNSIGNED NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS `text` VARCHAR(250) DEFAULT NULL,
            ADD COLUMN IF NOT EXISTS `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            ADD COLUMN IF NOT EXISTS `desc` TEXT,
            ADD INDEX IF NOT EXISTS `fk_] . $self->table . q[_parent_id_idx` (`parent_id` ASC),
            ADD CONSTRAINT `fk_] . $self->table . q[_parent_id_id`
                FOREIGN KEY IF NOT EXISTS (`parent_id`)
                REFERENCES ] . $self->dbh->quote_id( $self->table ) . q[ (`id`)
                ON DELETE CASCADE
                ON UPDATE CASCADE
        ;

        CREATE TABLE IF NOT EXISTS ] . $self->dbh->quote_id( $self->path_table ) . q[ (
            `node_id` BIGINT UNSIGNED NOT NULL,
            `parent_id` BIGINT UNSIGNED NOT NULL,
            INDEX `fk_] . $self->path_table . q[_node_id_idx` (`node_id` ASC),
            INDEX `fk_] . $self->path_table . q[_parent_id_idx` (`parent_id` ASC),
            PRIMARY KEY (`node_id`, `parent_id`),
            CONSTRAINT `fk_] . $self->path_table . q[_node_id`
                FOREIGN KEY (`node_id`)
                REFERENCES ] . $self->dbh->quote_id( $self->table ) . q[ (`id`)
                ON DELETE CASCADE
                ON UPDATE CASCADE,
            CONSTRAINT `fk_] . $self->path_table . q[_parent_id`
                FOREIGN KEY (`parent_id`)
                REFERENCES ] . $self->dbh->quote_id( $self->table ) . q[ (`id`)
                ON DELETE CASCADE
                ON UPDATE CASCADE
        ) ENGINE = InnoDB;
    ];

        $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES]] );
    }

    {
        my $sql = q[INSERT IGNORE INTO ] . $self->dbh->quote_id( $self->table ) . q[ SET `id` = 0, `parent_id` = 0, `depth` = 0;];

        $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES NO_AUTO_VALUE_ON_ZERO]] );
    }

    return;
};

sub _build_path_table {
    my $self = shift;

    return q[_] . $self->table . '_path';
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
            my $depth;

            # get parent node
            {
                my ( $sql, @bind ) = $self->sqla->select(
                    -columns => ['depth'],
                    -from    => $self->table,
                    -where   => { id => $rec->in_fields->{parent_id} },
                );

                $depth = $self->dbh->selectval( $sql, undef, {}, @bind ) // $self->exception(q[Parent node wasn't found]);
            }

            # insert node
            {
                $rec->in_fields->{depth} = ++$depth->$*;

                my ( $sql, @bind ) = $self->sqla->insert(
                    -into   => $self->table,
                    -values => $rec->in_fields,
                );

                $self->dbh->do( $sql, {}, @bind );
            }

            my $id = $self->dbh->last_insert_id;

            $rec->set_id($id);

            # update node paths cache
            {
                my $sql = 'INSERT INTO ' . $self->dbh->quote_id( $self->path_table ) . ' (`node_id`, `parent_id`) SELECT ?, `parent_id` FROM ' . $self->dbh->quote_id( $self->path_table ) . ' WHERE `node_id` = ? UNION ALL SELECT ?, ?';

                $self->dbh->do( $sql, {}, $id, $rec->in_fields->{parent_id}, $id, $rec->in_fields->{parent_id} );
            }
        }

        $self->dbh->commit;

        # read all inserted records
        my ( $sql, @bind ) = $self->sqla->select(
            -columns => $call->persist_fields,
            -from    => $self->table,
            -where   => { id => { -in => $records->get_primary_keys } }
        );

        $recs = $self->dbh->selectall( $sql, {}, @bind );
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

    my $id        = $params->{id}->value;
    my $min_depth = $params->{min_depth}->value;
    my $max_depth = $params->{max_depth}->value;

    my $root_depth;

    if ($max_depth) {
        my ( $sql, @bind ) = $self->sqla->select(
            -columns => 'depth',
            -from    => $self->table,
            -where   => { id => $id, },
        );

        $root_depth = $self->dbh->selectval( $sql, undef, {}, @bind ) // return;
    }

    if ( my $recs = $self->db_get_subtree( $id, min_depth => $min_depth, max_depth => $max_depth ) ) {
        my $loaded_depth = $max_depth ? $root_depth->$* + $max_depth : undef;

        for my $rec ( $recs->@* ) {
            $rec->{leaf} = $FALSE;

            if ($max_depth) {
                $rec->{loaded} = $rec->{depth} < $loaded_depth ? $TRUE : $FALSE;
            }
            else {
                $rec->{loaded} = $TRUE;
            }
        }

        return $recs;
    }

    return;
}

# API UPDATE
# TODO implement move node
sub on_api_update_read_record {
    my $self = shift;
    my $rec  = shift;

    if ( exists $rec->in_fields->{parent_id} ) {

        # read and cache original row
        my ( $sql, @bind ) = $self->sqla->select(
            -columns => [ 'id', 'parent_id', 'text' ],
            -from    => $self->table,
            -where => { id => $rec->id }
        );

        if ( my $orig_rec = $self->dbh->selectrow( $sql, {}, @bind ) ) {

            # TODO implement move node
            $self->exception(q[Moving node not supported yet]) if $orig_rec->{parent_id} != $rec->in_fields->{parent_id};
        }
        else {
            $self->exception( q[Can't update id = "] . $rec->id . q["] );
        }
    }

    return;
}

# DBH METHODS
# get subtree, excuding parent node
sub db_get_subtree {
    my $self = shift;
    my $id   = shift // 0;
    my %args = (
        min_depth => 0,    # depth is relative to select id
        max_depth => 0,
        @_,
    );

    if ( $args{min_depth} && !$args{max_depth} ) {
        my ( $sql, @bind ) = $self->sqla->select(
            -columns => 'n.*',
            -from    => [ -join => $self->table . q[|n], '<=>id=node_id', $self->path_table . q[|p] ],
            -where   => {
                'n.id'        => { q[!=], $id },
                'p.parent_id' => $id,
                'n.depth' => { '>', \[ '(SELECT `depth` + ? AS min_depth FROM `' . $self->table . '` WHERE `id` = ?)', $args{min_depth}, $id ] },
            },
            -order_by => [ '+depth', '+index' ],
        );

        return $self->dbh->selectall( $sql, {}, @bind );
    }
    elsif ( !$args{min_depth} && $args{max_depth} ) {
        my ( $sql, @bind ) = $self->sqla->select(
            -columns => 'n.*',
            -from    => [ -join => $self->table . q[|n], '<=>id=node_id', $self->path_table . q[|p] ],
            -where   => {
                'n.id'        => { q[!=], $id },
                'p.parent_id' => $id,
                'n.depth' => { '<=', \[ '(SELECT `depth` + ? AS max_depth FROM `' . $self->table . '` WHERE `id` = ?)', $args{max_depth}, $id ] },
            },
            -order_by => [ '+depth', '+index' ],
        );

        return $self->dbh->selectall( $sql, {}, @bind );
    }
    elsif ( $args{min_depth} && $args{max_depth} ) {
        my ( $sql, @bind ) = $self->sqla->select(
            -columns => 'n.*',
            -from    => [ -join => $self->table . q[|n], '<=>id=node_id', $self->path_table . q[|p] ],
            -where   => {
                'n.id'        => { q[!=], $id },
                'p.parent_id' => $id,
                'n.depth'     => [
                    '-and',    #
                    { '>',  \[ '(SELECT `depth` + ? AS min_depth FROM `' . $self->table . '` WHERE `id` = ?)', $args{min_depth}, $id ] },
                    { '<=', \[ '(SELECT `depth` + ? AS max_depth FROM `' . $self->table . '` WHERE `id` = ?)', $args{max_depth}, $id ] },
                ],
            },
            -order_by => [ '+depth', '+index' ],
        );

        return $self->dbh->selectall( $sql, {}, @bind );
    }
    else {
        my ( $sql, @bind ) = $self->sqla->select(
            -columns => 'n.*',
            -from    => [ -join => $self->table . q[|n], '<=>id=node_id', $self->path_table . q[|p] ],
            -where   => {
                'n.id'        => { '<>', $id },
                'p.parent_id' => $id,
            },
            -order_by => [ '+depth', '+index' ],
        );

        return $self->dbh->selectall( $sql, {}, @bind );
    }
}

# return all parents including requested node and excluding root node, return undef if node not exists
sub db_get_parent_nodes {
    my $self = shift;
    my $id   = shift;

    my ( $sql, @bind ) = $self->sqla->select(
        -columns => 'n.*',
        -from    => [ -join => $self->table . q[|n], qq[=>id=parent_id,p.node_id='$id'], $self->path_table . q[|p] ],
        -where   => {
            'n.id' => { q[!=], 0 },
            -or    => [
                'n.id'      => $id,
                'p.node_id' => $id,
            ],
        },
        -order_by => ['+depth'],
    );

    return $self->dbh->selectall( $sql, {}, @bind );
}

# remove node subtree, exculding node
sub db_remove_subtree {
    my $self = shift;
    my $id   = shift;

    return $self->dbh->query( 'DELETE FROM', \$self->table, 'WHERE parent_id = ', \$id )->do;
}

# EXT MODEL
sub _build_ext_model_base_class {
    my $self = shift;

    return 'Ext.data.TreeModel';
}

# EXT TREE PANEL
sub ext_class_panel {
    my $self = shift;

    return $self->ext_define(
        'Pcore.tree.Panel',
        {   rootId               => 0,
            createFormPanelClass => $self->ext_class('FormPanel'),
            updateFormPanelClass => $self->ext_class('FormPanel'),

            viewModel => {
                stores => {    #
                    store => $self->ext_class_store,
                },
            },
        }
    );
}

# EXT TREE STORE
sub ext_class_store {
    my $self = shift;

    return $self->ext_define(
        'Ext.data.TreeStore',
        {   autoLoad      => $FALSE,
            defaultRootId => undef,
            model         => $self->ext_class( 'Model', require => 1 ),
            root          => {
                id       => undef,
                expanded => $FALSE
            }
        },
    );
}

# EXT EDIT FORM PANEL
sub ext_class_form_panel {
    my $self = shift;

    return $self->ext_define(
        'Pcore.form.Panel',
        {   items => [
                {   name       => 'text',
                    xtype      => 'textfield',
                    fieldLabel => 'Text',
                    bind       => '{editModel.text}',
                },
                {   name       => 'desc',
                    xtype      => 'textareafield',
                    fieldLabel => 'Description',
                    bind       => '{editModel.desc}',
                },
            ],
        }
    );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 70, 71, 78, 79, 81,  │ ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               │
## │      │ 86, 89, 90, 92, 94,  │                                                                                                                │
## │      │ 97, 99               │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
