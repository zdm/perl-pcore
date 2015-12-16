package Pcore::API::Class::Upload::File;

use Pcore -role;
use Imager;

with qw[Pcore::API::Class::Grid];

requires qw[_build_folder_api _build_location];

has folder_api     => ( is => 'lazy', isa => Str, init_arg => undef );
has location       => ( is => 'lazy', isa => Str, init_arg => undef );
has root           => ( is => 'lazy', isa => Str, init_arg => undef );
has thumb_size     => ( is => 'lazy', isa => Int, init_arg => undef );
has _thumb_postfix => ( is => 'lazy', isa => Str, init_arg => undef );

our $MIME_CATEGORY_GLYPH = {
    q[]        => 0xf016,    # default
    archive    => 0xf1c6,
    audio      => 0xf1c7,
    code       => 0xf1c9,
    excel      => 0xf1c3,
    image      => 0xf1c5,
    pdf        => 0xf1c1,
    powerpoint => 0xf1c4,
    text       => 0xf0f6,
    video      => 0xf1c8,
    word       => 0xf1c2,
};

our $FILENAME_TYPE = FileNameStr;

our $FIELDS = {
    folder_id => { type => 'int', persist => 'rw', write_field => 1 },

    # TODO validators => [ { type => 'presence' }, { type => 'filename' } ]
    name    => { type => 'str',  persist => 'rw', isa_type    => FileNameStr, write_field => 1 },
    desc    => { type => 'str',  persist => 'rw', null        => 1,           blank       => 1 },
    size    => { type => 'int',  persist => 'ro', write_field => 1 },
    created => { type => 'date', persist => 'ro', write_field => 1 },

    location => { type => 'str', write_field => 1, depends => [ 'folder_id', 'name' ] },
    glyph    => { type => 'int', write_field => 1, depends => ['name'] },
    thumb    => { type => 'str', write_field => 1, depends => ['location'] },

    file => { type => 'upload' },
};

our $METHODS = {
    read => {
        type   => 'read',
        params => [ { type => 'id', }, { type => 'fields' }, { type => 'filter', }, { type => 'sort', default_value => ['+name'], }, ],
        public => 1,
    },
};

around BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig(@_);

    $FIELDS->{thumb}->{ext}->{convert} = $self->js_func(
        [ 'value', 'record' ], <<'JS'
            if(value){
                value = Ext.urlAppend(value, '_dc=' + (new Date().getTime()));
            }

            return value;
JS
    );

    $self->add_fields($FIELDS);

    $self->add_methods($METHODS);

    return;
};

# DDL
around APP_BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig;

    $self->get_api_obj( $self->folder_api )->APP_BUILD;

    my $sql = q[
        ALTER TABLE ] . $self->dbh->quote_id( $self->table ) . q[
            ADD COLUMN IF NOT EXISTS `folder_id` BIGINT UNSIGNED NOT NULL,
            ADD COLUMN IF NOT EXISTS `name` VARCHAR(255) NOT NULL,
            ADD COLUMN IF NOT EXISTS `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            ADD COLUMN IF NOT EXISTS `desc` TEXT,
            ADD COLUMN IF NOT EXISTS `size` INT UNSIGNED NULL,
            ADD UNIQUE INDEX IF NOT EXISTS `] . $self->table . q[_folder_id_name_UNIQUE` (`folder_id` ASC, `name` ASC),
            ADD CONSTRAINT `fk_] . $self->table . q[_folder_id_id`
                FOREIGN KEY IF NOT EXISTS (`folder_id`)
                REFERENCES ] . $self->dbh->quote_id( $self->get_api_obj( $self->folder_api )->table ) . q[ (`id`)
                ON DELETE CASCADE
                ON UPDATE CASCADE
        ;
    ];

    $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES]] );

    return;
};

no Pcore;

sub _build_thumb_size {
    my $self = shift;

    return 200;
}

sub _build__thumb_postfix {
    my $self = shift;

    return q[_] . $self->thumb_size . q[x] . $self->thumb_size . '.jpg';
}

sub _build_root {
    my $self = shift;

    return $self->get_api_obj( $self->folder_api )->root;
}

# API CREATE
sub on_api_create_read_record {
    my $self = shift;
    my $rec  = shift;

    # get and validate filename
    if ( !exists $rec->in_fields->{name} ) {
        $rec->in_fields->{name} = $rec->uploads->{file}->[0]->filename;

        $self->exception( q[File name isn't valid], errors => { name => q[File name isn't valid] } ) if !$FILENAME_TYPE->check( $rec->in_fields->{name} );
    }

    # fill size field
    $rec->in_fields->{size} = $rec->uploads->{file}->[0]->size;

    return;
}

sub on_api_create_write_record {
    my $self = shift;
    my $rec  = shift;

    my $folder_path = $self->root . $self->get_folder_path( $rec->out_fields->{folder_id} );

    P->file->mkpath($folder_path);

    $rec->uploads->{file}->[0]->move( $folder_path . $rec->out_fields->{name} );

    # create thumbnail
    $self->_create_thumb( $rec->uploads->{file}->[0]->path );

    return;
}

# API UPDATE
sub on_api_update_read_record {
    my $self = shift;
    my $rec  = shift;

    # read and cache original record
    my ( $sql, @bind ) = $self->sqla->select(
        -columns => [ 'name', 'folder_id' ],
        -from    => $self->table,
        -where => { id => $rec->id }
    );

    if ( my $orig_rec = $self->dbh->selectrow( $sql, {}, @bind ) ) {

        # cache original record
        $rec->set_orig_record($orig_rec);
    }
    else {
        $self->exception( q[Can't update id = "] . $rec->id . q["] );
    }

    return;
}

sub on_api_update_write_record {
    my $self = shift;
    my $rec  = shift;

    my $current_folder_path = $self->get_folder_path( $rec->out_fields->{folder_id} );
    my $current_path        = $current_folder_path . $rec->out_fields->{name};

    my $old_folder_path;
    my $old_path;

    # folder_id was changed
    if ( $rec->out_fields->{folder_id} != $rec->orig_fields->{folder_id} ) {
        $old_folder_path = $self->get_folder_path( $rec->orig_fields->{folder_id} );
    }

    # filename was changed
    if ( $rec->out_fields->{name} ne $rec->orig_fields->{name} ) {
        if ( defined $old_folder_path ) {
            $old_path = $old_folder_path . $rec->orig_fields->{name};
        }
        else {
            $old_path = $current_folder_path . $rec->orig_fields->{name};
        }
    }
    elsif ( defined $old_folder_path ) {
        $old_path = $old_folder_path . $rec->out_fields->{name};
    }

    P->file->mkpath($current_folder_path);

    if ( exists $rec->uploads->{file} ) {    # replace file, if new file uploaded
        if ($old_path) {
            ## no critic qw[InputOutput::RequireCheckedSyscalls]
            unlink $self->root . $old_path;
            unlink $self->root . $old_path . $self->_thumb_postfix;
        }

        $rec->uploads->{file}->[0]->move( $self->root . $current_path );

        # create thumbnail
        $self->_create_thumb( $rec->uploads->{file}->[0]->path );
    }
    elsif ($old_path) {                      # or move file to the new location if needed
        P->file->move( $self->root . $old_path, $self->root . $current_path );

        # unlink old thumbnail
        unlink $self->root . $old_path . $self->_thumb_postfix;    ## no critic qw[InputOutput::RequireCheckedSyscalls]

        # create thumbnail
        $self->_create_thumb( $self->root . $current_path );
    }

    return;
}

# API DESTROY
sub on_api_destroy_read_record {
    my $self = shift;
    my $rec  = shift;

    my ( $sql, @bind ) = $self->sqla->select(
        -columns => [qw[id folder_id name]],
        -from    => $self->table,
        -where   => { id => $rec->id },
    );

    if ( my $orig_rec = $self->dbh->selectrow( $sql, {}, @bind ) ) {
        $rec->set_orig_record($orig_rec);
    }

    return;
}

sub on_api_destroy_write_record {
    my $self = shift;
    my $rec  = shift;

    if ( $rec->has_orig_fields ) {
        my $path = $self->root . $self->get_folder_path( $rec->orig_fields->{folder_id} ) . $rec->orig_fields->{name};

        ## no critic qw[InputOutput::RequireCheckedSyscalls]
        unlink $path;
        unlink $path . $self->_thumb_postfix;
    }

    return;
}

# FIELDS
sub write_field_location {
    my $self = shift;
    my $val  = shift;
    my $rec  = shift;

    return if !defined $rec->out_fields->{name} || !defined $rec->out_fields->{folder_id};

    return \( $self->location . $self->get_folder_path( $rec->out_fields->{folder_id} ) . $rec->out_fields->{name} );
}

sub write_field_glyph {
    my $self = shift;
    my $val  = shift;
    my $rec  = shift;

    return if !defined $rec->out_fields->{name};

    my $path = P->path( $rec->out_fields->{name} );

    if ( exists $MIME_CATEGORY_GLYPH->{ $path->mime_category } ) {
        return \$MIME_CATEGORY_GLYPH->{ $path->mime_category };
    }
    else {
        return \$MIME_CATEGORY_GLYPH->{q[]};    # default glyph
    }
}

sub write_field_thumb {
    my $self = shift;
    my $val  = shift;
    my $rec  = shift;

    return if !defined $rec->out_fields->{name} || !defined $rec->out_fields->{location};

    my $path = P->path( $rec->out_fields->{name} );

    if ( $path->mime_category eq 'image' ) {
        return \( $rec->out_fields->{location} . $self->_thumb_postfix );
    }
    else {
        return;
    }
}

# UTIL
sub get_folder_path {
    my $self = shift;
    my $id   = shift;

    my $cache = $self->call_cache->{folder_path} //= {};

    if ( !exists $cache->{$id} ) {
        if ( my $res = $self->get_api_obj( $self->folder_api )->db_get_parent_nodes($id) ) {
            $cache->{$id} = join( q[/], map { $_->{text} } $res->@* ) . q[/];
        }
        else {
            $cache->{$id} = q[];
        }
    }

    return $cache->{$id};
}

sub _create_thumb {
    my $self = shift;
    my $path = shift;

    $path = P->path($path);

    if ( $path->mime_category eq 'image' ) {
        my $img = Imager->new( file => $path );

        return unless $img;

        my $img_scaled = $img->scale( xpixels => $self->thumb_size, ypixels => $self->thumb_size, type => 'min' );

        $img_scaled->write( file => $path . $self->_thumb_postfix, type => 'jpeg', jpegquality => 50 );
    }

    return;
}

# EXT PANEL
sub ext_class_panel {
    my $self = shift;

    return $self->ext_define(
        'Ext.panel.Panel',
        {    # customizations
            folderId             => undef,
            defaultViewType      => 'small',
            createFormPanelClass => $self->ext_class('FormPanel'),
            updateFormPanelClass => $self->ext_class('FormPanel'),
            _viewTypeNs          => $self->ext_class . 'View',

            # permissions
            canCreate      => $TRUE,
            canEdit        => $TRUE,
            canDelete      => $TRUE,
            selectCallback => $FALSE,

            controller => { type => $self->ext_type('ViewController') },
            viewModel  => {
                stores => {    #
                    store => $self->ext_class_store,
                },
                data => {
                    editModel      => undef,
                    selectedRecord => undef,
                },
            },

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
                    {   reference => 'upload_button',
                        text      => 'Upload',
                        glyph     => 0xf093,
                        handler   => 'createRecord',
                        width     => 150,
                    },
                    {   reference => 'remove_button',
                        text      => 'Delete',
                        glyph     => 0xf014,
                        disabled  => $TRUE,
                        handler   => 'deleteSelectedRecords',
                        bind      => { disabled => '{!selectedRecord}', },
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
                            {   glyph    => 0xf00b,
                                text     => 'Tile',
                                value    => 'tile',
                                disabled => $TRUE,
                            },
                            {   glyph => 0xf00a,
                                text  => 'Small',
                                value => 'small'
                            },
                            {   glyph => 0xf009,
                                text  => 'Large',
                                value => 'large'
                            }
                        ],
                    },
                    '->',
                    {   text    => 'Refresh',
                        glyph   => 0xf01e,
                        handler => 'reloadStore',
                    },
                ],
            },

            fbar => [
                {   reference => 'select_button',
                    text      => 'Select',
                    glyph     => 0xf00c,
                    scale     => 'small',
                    hidden    => $FALSE,
                    disabled  => $TRUE,
                    bind      => { disabled => '{!selectedRecord}', },
                    handler   => 'selectSelectedRecord'
                }
            ],

            # methods
            initComponent => $self->js_func(
                <<'JS'
                    this.callParent(arguments);

                    this.getViewModel().getStore('store').setFilters(
                        [
                            {
                                property: 'folder_id',
                                value: this.folderId,
                                operator: '='
                            }
                        ]
                    );

                    this.getViewModel().getStore('store').load();

                    if (!this.canCreate) this.lookupReference('upload_button').setDisabled(true);

                    if (!this.canDelete) {
                        var removeButton = this.lookupReference('remove_button')

                        removeButton.setDisabled(true);
                        removeButton.setBind({});
                    }

                    if (!this.selectCallback) this.lookupReference('select_button').setHidden(true);

                    // show initial view type panel
                    this.controller.setViewType(this.defaultViewType);
JS
            ),
        }
    );
}

# EXT VIEW CONTROLLER
sub ext_class_view_controller {
    my $self = shift;

    return $self->ext_define(
        'Pcore.grid.ViewController',
        {   createRecord => $self->js_func(
                <<'JS'
                    var model = this.getViewModel().getStore('store').createModel({
                        folderId: this.getView().folderId
                    });

                    var formPanel = this._createFormPanel(this.getView().createFormPanelClass, model, {
                        title: 'Upload file',
                        baseParams: {
                            folderId: model.get('folderId')
                        }
                    });

                    formPanel.on('recordUpdated', function (record) {
                        var store = this.getViewModel().get('store');

                        store.addSorted(record);

                        store.commitChanges();

                        this.fireViewEvent('recordUpdated', this, record);
                    }, this);

                    this._createFormPanelWindow(formPanel);
JS
            ),
            editRecord => $self->js_func(
                ['model'], <<'JS'
                    model.load({
                        scope: this,
                        success: function (record, operation) {
                            var formPanel = this._createFormPanel(this.getView().updateFormPanelClass, record, {
                                title: 'Edit file',
                            });

                            formPanel.lookupReference('file_upload_field').allowBlank = true;

                            formPanel.on('recordUpdated', function (record) {
                                this.fireViewEvent('recordUpdated', this, record);
                            }, this);

                            this._createFormPanelWindow(formPanel);
                        },
                    });
JS
            ),

            onViewTypeButtonToggle => $self->js_func(
                ['button'], <<'JS'
                    this.setViewType(button.getValue());
JS
            ),
            setViewType => $self->js_func(
                ['viewType'], <<'JS'
                    this.lookupReference('view_type_button').setValue(viewType);

                    var itemId = 'view_' + this.getView().folderId + '_' + viewType;

                    var view = this.getView().getComponent(itemId);

                    if (!view) {
                        var className = this.getView()._viewTypeNs + viewType;

                        view = Ext.create(className, {
                            itemId: itemId
                        });
                    }

                    this.getView().setActiveItem(view);

                    this.fireViewEvent('viewTypeChange', viewType);
JS
            ),

            downloadFile => $self->js_func(
                ['file'], <<'JS'
                    window.open(file.get('location'));
JS
            ),

            selectRecord => $self->js_func(
                ['file'], <<'JS'
                    if (this.getView().selectCallback) this.getView().selectCallback(file);
JS
            ),
            selectSelectedRecord => $self->js_func(
                <<'JS'
                    this.selectRecord(this.getViewModel().get('selectedRecord'));
JS
            ),

            onRecordContextMenu => $self->js_func(
                [qw[panel file el index e eOpts]], <<'JS'
                    e.stopEvent();

                    var menuItems = [];

                    if(this.getView().canEdit){
                        menuItems.push(Ext.create('Ext.Action', {
                            text: 'Edit',
                            glyph: 0xf044,
                            scope: this,
                            handler: function () {
                                this.editRecord(file);
                            }
                        }));
                    }

                    if(this.getView().canDelete){
                        menuItems.push(Ext.create('Ext.Action', {
                            text: 'Delete',
                            glyph: 0xf014,
                            scope: this,
                            handler: function () {
                                this.deleteRecords([file]);
                            }
                        }));
                    }

                    menuItems.push(Ext.create('Ext.Action', {
                        text: 'Download',
                        glyph: 0xf019,
                        scope: this,
                        handler: function () {
                            this.downloadFile(file);
                        }
                    }));

                    if(this.getView().selectCallback){
                        menuItems.push(Ext.create('Ext.Action', {
                            text: 'Select',
                            glyph: 0xf00c,
                            scope: this,
                            handler: function () {
                                this.selectRecord(file);
                            }
                        }));
                    }

                    if (menuItems.length) {
                        Ext.create('Ext.menu.Menu', {
                            items: menuItems,
                            listeners: {
                                hide: function (me) {
                                    Ext.destroy(me);
                                }
                            }
                        }).showAt(e.getXY());
                    }

                    return false;
JS
            ),

            onRecordDblClick => $self->js_func(
                [ 'component', 'file' ], <<'JS'
                    if(this.getView().selectCallback){
                        this.selectRecord(file);
                    }
                    else{
                        this.downloadFile(file);
                    }
JS
            ),
        }
    );
}

# EXT STORE
sub ext_class_store {
    my $self = shift;

    return $self->ext_define(
        'Ext.data.Store',
        {   autoLoad     => $FALSE,
            pageSize     => undef,
            remoteSort   => $TRUE,
            remoteFilter => $TRUE,
            autoFilter   => $FALSE,
            model        => $self->ext_class( 'Model', require => 1 ),
        },
    );
}

# EXT EDIT FORM PANEL
sub ext_class_form_panel {
    my $self = shift;

    return $self->ext_define(
        'Pcore.form.Panel',
        {   commitFormOnSave => $TRUE,
            items            => [
                {   name           => 'file',
                    reference      => 'file_upload_field',
                    xtype          => 'fileuploadfield',
                    fieldLabel     => q[ ],
                    allowBlank     => $FALSE,
                    clearOnSubmit  => $FALSE,
                    buttontext     => 'select file...',
                    labelSeparator => q[],
                    listeners      => {
                        change => $self->js_func(
                            [qw[me value]], <<'JS'
                        var form = this.up('form');
                        var fielNameField = form.lookupReference('file_name_field');

                        if(form.getViewModel().get('editModel').phantom){
                            fielNameField.setValue(me.getFilename());
                        }
                        else{
                            if(!fielNameField.getValue()){
                                fielNameField.setValue(me.getFilename());
                            }
                        }
JS
                        ),
                        scope => 'this',
                    },
                },
                {   name       => 'name',
                    itemId     => 'nameField',
                    reference  => 'file_name_field',
                    xtype      => 'textfield',
                    fieldLabel => 'File name',
                    bind       => '{editModel.name}',
                },
                {   name       => 'desc',
                    xtype      => 'textareafield',
                    fieldLabel => 'Description',
                    bind       => '{editModel.desc}',
                }
            ],
        }
    );
}

# EXT VIEWS
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

            columns => [
                {   dataIndex => 'name',
                    text      => 'Имя',
                    flex      => 1,
                },
                {   dataIndex => 'size',
                    text      => 'Size',
                },
                {   dataIndex => 'location',
                    text      => 'Location',
                    flex      => 1,
                }
            ],
        }
    );
}

sub ext_class_panel_viewtile {
    my $self = shift;

    return $self->ext_define(
        'PanelViewsmall',
        {   thumbWidth  => 50,
            thumbHeight => 50,
        }
    );
}

sub ext_class_panel_viewsmall {
    my $self = shift;

    return $self->ext_define(
        'Ext.view.View',
        {   thumbWidth        => 80,
            thumbHeight       => 80,
            defaultThumbGlyph => 0xf016,

            autoScroll              => $TRUE,
            itemSelector            => 'div.x-filebrowser-thumb',
            overItemCls             => 'x-filebrowser-thumb-over',
            preserveScrollOnRefresh => $TRUE,
            trackOver               => $TRUE,

            mixins => {
                dragSelector => 'Ext.ux.DataView.DragSelector',
                draggable    => 'Ext.ux.DataView.Draggable'
            },

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
                                '<tpl if="values.thumb">',
                                    '<img src="{thumb}" style="max-width:' + this.thumbWidth + 'px; max-height:' + this.thumbHeight + 'px; width:auto; height:auto;" />',
                                '<tpl else>',
                                    '<font style="font-size:20px; font-family:FontAwesome;">{[this.getGlyph(values.glyph)]}</font>',
                                '</tpl>',
                                '</td></tr>',
                                '<tr><td align="center" style="overflow:hidden; white-space:nowrap; text-overflow:ellipsis;" data-qtip="{name}<br>{desc}">{name}</td></tr>',
                            '</table>',
                        '</div>',
                    '</tpl>',
                    {
                        getGlyph: function (glyph) {
                            return String.fromCharCode(glyph || this.defaultThumbGlyph);
                        }
                },
                this];

                return tpl;
JS
            ),
            initComponent => $self->js_func(
                <<'JS'
                Ext.util.CSS.createStyleSheet('.x-filebrowser-thumb-over {background-color:#EBEBEB;}');

                Ext.util.CSS.createStyleSheet('div.x-filebrowser-thumb.x-item-selected {background-color:#EBEBEB;}');

                this.tpl = this.createTpl();

                this.callParent(arguments);

                this.mixins.dragSelector.init(this);
                this.mixins.draggable.init(this, {
                    ddConfig: {
                        ddGroup: this.ddGroup
                    },
                });
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

sub ext_class_panel_viewlarge {
    my $self = shift;

    return $self->ext_define(
        'PanelViewsmall',
        {   thumbWidth  => 150,
            thumbHeight => 150,
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
## │    3 │ 88, 89, 95, 96, 98   │ ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
