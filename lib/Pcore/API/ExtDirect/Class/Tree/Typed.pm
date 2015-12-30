package Pcore::API::Class::Tree::Typed;

use Pcore -role;

with qw[Pcore::API::Class::Tree];

requires qw[_build_node_type_api];

has node_type_api => ( is => 'lazy', isa => Str, init_arg => undef );

our $FIELDS = {

    # system fields
    node_type       => { type => 'int', persist => 'rw', ext => { validators => [ { type => 'presence' } ] } },
    node_type_text  => { type => 'str', depends => ['node_type'] },
    node_type_class => { type => 'str', depends => ['node_type'] },
};

around BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig(@_);

    $self->add_fields($FIELDS);

    return;
};

# DDL
around APP_BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig;

    $self->get_api_obj( $self->node_type_api )->APP_BUILD;

    my $sql = q[
        ALTER TABLE ] . $self->dbh->quote_id( $self->table ) . q[
            ADD COLUMN IF NOT EXISTS `node_type` BIGINT UNSIGNED NOT NULL,
            ADD CONSTRAINT `fk_] . $self->table . q[_node_type_id`
                FOREIGN KEY IF NOT EXISTS (`node_type`)
                REFERENCES ] . $self->dbh->quote_id( $self->get_api_obj( $self->node_type_api )->table ) . q[ (`id`)
                ON DELETE CASCADE
                ON UPDATE CASCADE
        ;
    ];

    $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES]] );

    return;
};

# FIELDS METHODS
sub write_field_node_type_text {
    my $self = shift;
    my $val  = shift;
    my $rec  = shift;

    return \$self->get_node_types->{ $rec->out_fields->{node_type} }->{text};
}

sub write_field_node_type_class {
    my $self = shift;
    my $val  = shift;
    my $rec  = shift;

    return \$self->get_node_types->{ $rec->out_fields->{node_type} }->{class};
}

sub get_node_types {
    my $self = shift;

    if ( !exists $self->call_cache->{node_types} ) {
        my ( $sql, @bind ) = $self->sqla->select( -from => $self->get_api_obj( $self->node_type_api )->table );

        $self->call_cache->{node_types} = $self->dbh->selectall_hashref( $sql, 'id', {}, @bind ) // {};
    }

    return $self->call_cache->{node_types};
}

# EXT FORM PANEL
sub ext_class_form_panel {
    my $self = shift;

    return $self->ext_define(
        'Pcore.form.Panel',
        {   nodeTypeModelClass => $self->ext_class( $self->node_type_api . '.Model', require => 1 ),

            initComponent => $self->js_func(
                <<'JS'
                    this.callParent(arguments);

                    var nodeTypeStore = Ext.create('Ext.data.Store', {
                        autoDestroy: true,
                        autoLoad: false,
                        autoFilter: false,
                        remoteFilter: true,
                        pageSize: 10,
                        model: this.nodeTypeModelClass,
                        filters: {
                            property: 'id',
                            value: this.editModel.get('nodeType'),
                            operator: '='
                        }
                    });

                    this.getViewModel().set('nodeTypeStore', nodeTypeStore);
JS
            ),

            items => [
                {   name       => 'text',
                    xtype      => 'textfield',
                    fieldLabel => 'Text',
                    bind       => '{editModel.text}',
                },
                {   name       => 'nodeType',
                    xtype      => 'combobox',
                    fieldLabel => 'Node type',
                    bind       => { store => '{nodeTypeStore}', },
                    listeners  => {
                        select => $self->js_func(
                            [ 'cmp', 'records' ], <<'JS'
                                cmp.up('form').getViewModel().get('editModel').set('nodeType', records[0].getId());
JS
                        ),
                    },
                    beforeQuery => $self->js_func(
                        ['queryPlan'],
                        <<'JS'
                            this.store.removeFilter('id');

                            this.store.setFilters({
                                property: 'text',
                                value: queryPlan.query + '%',
                                operator: 'like'
                            });

                            return queryPlan;
JS
                    ),
                    autoLoadOnValue => $TRUE,
                    allowBlank      => $FALSE,
                    triggerAction   => 'last',
                    pageSize        => 10,
                    valueField      => 'id',
                    dispayField     => 'text',
                    forceSelection  => $TRUE,
                    queryMode       => 'remote',
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
## │    3 │ 39, 40, 42, 44       │ ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
