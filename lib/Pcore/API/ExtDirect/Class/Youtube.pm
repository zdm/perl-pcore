package Pcore::API::Class::Youtube;

use Pcore -role;

with qw[Pcore::API::Class::Grid];

requires qw[_build_google_api_name];

has google_api_name => ( is => 'lazy', isa => Str, init_arg => undef );
has google_api => ( is => 'lazy', isa => InstanceOf ['Pcore::Handle::API::Google'], init_arg => undef, weak_ref => 1 );

our $FIELDS = {
    yt_id    => { type => 'str', persist => 'rc', write_field => 1 },
    yt_title => { type => 'str', persist => 'ro', write_field => 1 },
    yt_desc  => { type => 'str', persist => 'ro' },
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

    my $sql = q[
        ALTER TABLE ] . $self->dbh->quote_id( $self->table ) . q[
            ADD COLUMN IF NOT EXISTS `yt_id` VARCHAR(255) NOT NULL,
            ADD COLUMN IF NOT EXISTS `yt_title` VARCHAR(1024) NOT NULL,
            ADD COLUMN IF NOT EXISTS `yt_desc` TEXT,
            ADD INDEX IF NOT EXISTS `] . $self->table . q[_yt_id` (`yt_id` ASC)
        ;
    ];

    $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES]] );

    return;
};

# EXT PANEL VIEW CONTROLLER
# around ext_class_panel_view_controller => sub {
#     my $orig = shift;
#     my $self = shift;
#
#     return $self->$orig->apply(
#         {   _createFormPanel => $self->js_func(
#                 ['model'], <<'JS'
#                     var formBaseParams = {};
#
#                     // if(model.phantom){
#                     //     formBaseParams.clientId = model.getId();
#                     //     formBaseParams.folderId = model.get('folderId');
#                     // }
#                     // else{
#                     //     formBaseParams.id = model.getId();
#                     // }
#
#                     var formPanel = Ext.create(this.getView().formPanelClass, {
#                         itemId: 'editForm',
#                         viewModel: {
#                             parent: this.getViewModel(),
#                         },
#                         editModel: model,
#                         // baseParams: formBaseParams,
#                         // api: {
#                         //     submit: model.phantom ? model.getProxy().api.create : model.getProxy().api.update
#                         // }
#                     });
#
#                     return formPanel;
# JS
#             ),
#             _renderFormPanel => $self->js_func(
#                 ['formPanel'],
#                 <<'JS'
#                     this._renderFormPanelWindow(formPanel, {
#                         title: 'Add YouTube video'
#                     });
# JS
#             ),
#             onViewTypeButtonToggle => $self->js_func(
#                 ['button'], <<'JS'
#                     this.switchViewType(button.getValue());
# JS
#             ),
#             switchViewType => $self->js_func(
#                 ['viewType'], <<'JS'
#                     this.lookupReference('view_type_button').setValue(viewType);
#
#                     var refName = 'view_' + viewType;
#
#                     var view = this.lookupReference(refName);
#
#                     if (!view) {
#                         var className = this.getView()._viewTypeNs + viewType;
#
#                         view = Ext.create(className, {
#                             reference: refName,
#                             itemId: refName
#                         });
#                     }
#
#                     this.getView().setActiveItem(view);
#
#                     this.fireViewEvent('viewType', viewType);
# JS
#             ),
#
#             #             downloadFile => $self->js_func(
#             #                 ['file'], <<'JS'
#             #                     window.open(file.get('location'));
#             # JS
#             #             ),
#             onRecordContextMenu => $self->js_func(
#                 [qw[panel file el index e eOpts]], <<'JS'
#                     e.stopEvent();
#
#                     var menuItems = [];
#
#                     if(this.getView().canEdit){
#                         menuItems.push(Ext.create('Ext.Action', {
#                             text: 'Edit',
#                             glyph: 0xf044,
#                             scope: this,
#                             handler: function () {
#                                 this.editRecord(file);
#                             }
#                         }));
#                     }
#
#                     if(this.getView().canDelete){
#                         menuItems.push(Ext.create('Ext.Action', {
#                             text: 'Delete',
#                             glyph: 0xf014,
#                             scope: this,
#                             handler: function () {
#                                 this.deleteRecords([file]);
#                             }
#                         }));
#                     }
#
#                     menuItems.push(Ext.create('Ext.Action', {
#                         text: 'Download',
#                         glyph: 0xf019,
#                         scope: this,
#                         handler: function () {
#                             this.downloadFile(file);
#                         }
#                     }));
#
#                     if(this.getView().selectCallback){
#                         menuItems.push(Ext.create('Ext.Action', {
#                             text: 'Select',
#                             glyph: 0xf00c,
#                             scope: this,
#                             handler: function () {
#                                 this.selectRecord(file);
#                             }
#                         }));
#                     }
#
#                     if (menuItems.length) {
#                         Ext.create('Ext.menu.Menu', {
#                             items: menuItems,
#                             listeners: {
#                                 hide: function (me) {
#                                     Ext.destroy(me);
#                                 }
#                             }
#                         }).showAt(e.getXY());
#                     }
#
#                     return false;
# JS
#             ),
#             onRecordDblClick => $self->js_func(
#                 [ 'component', 'model' ], <<'JS'
#                     this.editRecord(model);
# JS
#             ),
#         }
#     );
# };

# EXT FORM
# around ext_class_form_panel => sub {
#     my $orig = shift;
#     my $self = shift;
#
#     return $self->$orig->apply(
#         {   fbar => {
#                 items => [
#                     '->',
#                     {   text    => 'Save',
#                         glyph   => 0xf00c,
#                         handler => 'saveForm',
#                     },
#                     {   text    => 'Cancel',
#                         glyph   => 0xf00d,
#                         handler => 'cancelEdit',
#                     }
#                 ],
#             },
#             cancelEdit => $self->js_func(
#                 <<'JS'
#                     this.getViewModel().get('editModel').reject();
#
#                     this.closeForm();
# JS
#             ),
#         }
#     );
# };

sub _build_google_api {
    my $self = shift;

    my $google_api_name = $self->google_api_name;

    return $self->h_cache->$google_api_name;
}

# API CREATE
sub on_api_create_read_record {
    my $self = shift;
    my $rec  = shift;

    my $yt_id = $rec->in_fields->{yt_id};

    if ( $yt_id =~ /v=([^&]+)/sm ) {
        $yt_id = $1;
        $rec->in_fields->{yt_id} = $yt_id;
    }

    my $yt_res = $self->google_api->call( 'youtube/videos#read', { id => [$yt_id], part => [qw[snippet]] } );

    $self->exception('YouTube video not exists') unless exists $yt_res->{$yt_id};

    $rec->in_fields->{yt_title} = $yt_res->{$yt_id}->{snippet}->{title};
    $rec->in_fields->{yt_desc}  = $yt_res->{$yt_id}->{snippet}->{description};

    return;
}

# EXT PANEL
sub ext_class_panel {
    my $self = shift;

    return $self->ext_define(
        'Ext.panel.Panel',
        {   controller => { type => $self->ext_type('PanelViewController') },
            viewModel  => $self->ext_class_panel_view_model,

            # customizations
            folderId        => undef,
            defaultViewType => 'list',
            formPanelClass  => $self->ext_class('FormPanel'),

            _viewTypeNs => $self->ext_class . 'View',

            # layout
            layout => 'card',
            items  => [],

            # tbar
            tbar => {
                enableOverflow => $TRUE,

                defaults => {
                    scale     => 'small',
                    iconAlign => 'top',
                    minWidth  => 70,
                },
                items => [
                    {   text    => 'Add',
                        glyph   => 0xf016,
                        handler => 'createRecord',
                    },
                    {   text     => 'Delete',
                        glyph    => 0xf014,
                        disabled => $TRUE,
                        handler  => 'deleteSelectedRecords',
                        bind     => { disabled => '{!selectedRecord}', },
                    },
                    '->',
                    {   reference => 'view_type_button',
                        xtype     => 'segmentedbutton',

                        allowDepress  => $FALSE,
                        allowMultiple => $FALSE,

                        listeners => { toggle => 'onViewTypeButtonToggle', },

                        defaults => {
                            iconAlign => 'top',
                            scale     => 'small',
                            width     => 70,
                            xtype     => 'button'
                        },
                        items => [
                            {   glyph => 0xf0c9,
                                text  => 'List',
                                value => 'list',
                            },
                            {   glyph => 0xf009,
                                text  => 'Video',
                                value => 'video'
                            },
                        ],
                    },
                    '->',
                    {   text    => 'Refresh',
                        glyph   => 0xf01e,
                        handler => 'reloadStore',
                    },
                ],
            },

            # methods
            initComponent => $self->js_func(
                <<'JS'
                    this.callParent();

                    // this.getViewModel().getStore('store').setFilters(
                    //     [
                    //         {
                    //             property: 'folder_id',
                    //             value: this.folderId,
                    //             operator: '='
                    //         }
                    //     ]
                    // );

                    this.getViewModel().getStore('store').load();

                    // show initial view type panel
                    this.controller.switchViewType(this.defaultViewType);
JS
            ),
        }
    );
}

sub ext_class_panel_viewlist {
    my $self = shift;

    return $self->ext_define(
        'Ext.grid.Panel',
        {   allowDeselect => $TRUE,

            bind => {
                store     => '{store}',
                selection => '{selectedRecord}',
            },

            selType  => 'checkboxmodel',
            selModel => {
                checkOnly          => $TRUE,
                mode               => 'SINGLE',
                showHeaderCheckbox => $FALSE,
                toggleOnClick      => $FALSE,
            },

            listeners => {
                rowDblClick    => 'onRecordDblClick',
                rowContextMenu => 'onRecordContextMenu',
            },

            columns => $self->_get_grid_columns,
        }
    );
}

sub ext_class_panel_viewvideo {
    my $self = shift;

    return $self->ext_define(
        'Ext.view.View',
        {   thumbWidth  => 200,
            thumbHeight => 170,

            autoScroll              => $TRUE,
            itemSelector            => 'div.x-filebrowser-thumb',
            overItemCls             => 'x-filebrowser-thumb-over',
            preserveScrollOnRefresh => $TRUE,
            trackOver               => $TRUE,

            # mixins => {
            #     dragSelector => 'Ext.ux.DataView.DragSelector',
            #     draggable    => 'Ext.ux.DataView.Draggable'
            # },

            bind => {
                store     => '{store}',
                selection => '{selectedRecord}',
            },

            createTpl => $self->js_func(
                <<'JS'
                var tpl = [
                    '<tpl for=".">',
                        '<div class="x-filebrowser-thumb" style="display: inline-block; padding:3px;">',
                            '<table border="0" cellspacing="0" cellpadding="0" style="width:0px; table-layout:fixed;">',
                                '<tr><td width="' + this.thumbWidth + '" height="' + this.thumbHeight + '" align="center" valign="middle" style="background-color:#F9F9F9;">',
                                    '<iframe width="100%" height="100%" src="//www.youtube.com/embed/{ytId}?rel=0&amp;showinfo=0" frameborder="0" allowfullscreen></iframe>',
                                '</td></tr>',
                                '<tr><td align="center" style="overflow:hidden; white-space:nowrap; text-overflow:ellipsis;" data-qtip="{ytTitle}<br>{ytDesc}">{ytTitle}</td></tr>',
                            '</table>',
                        '</div>',
                    '</tpl>',
                ];

                return tpl;
JS
            ),
            initComponent => $self->js_func(
                <<'JS'
                Ext.util.CSS.createStyleSheet('.x-filebrowser-thumb-over {background-color:#EBEBEB;}');

                Ext.util.CSS.createStyleSheet('div.x-filebrowser-thumb.x-item-selected {background-color:#EBEBEB;}');

                this.tpl = this.createTpl();

                this.callParent(arguments);

                // this.mixins.dragSelector.init(this);
                // this.mixins.draggable.init(this, {
                //     ddConfig: {
                //         ddGroup: this.ddGroup
                //     },
                // });
JS
            ),

            # listeners
            listeners => {
                itemDblClick    => 'onRecordDblClick',
                itemContextMenu => 'onRecordContextMenu'
            }
        }
    );
}

sub _get_grid_columns {
    my $self = shift;

    return [
        {   text      => 'YouTube Id',
            dataIndex => 'ytId',
        },
        {   text      => 'Title',
            dataIndex => 'ytTitle',
            flex      => 1,
        },
    ];
}

sub _get_form_items {
    my $self = shift;

    return [
        {   name       => 'ytId',
            xtype      => 'textfield',
            fieldLabel => 'YouTube url or id',
            bind       => '{editModel.ytId}',
            labelWidth => 115,
        },
    ];
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 36, 37, 41           | ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 468                  | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_get_form_items' declared but not   |
## |      |                      | used                                                                                                           |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
