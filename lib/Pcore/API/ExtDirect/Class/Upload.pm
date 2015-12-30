package Pcore::API::Class::Upload;

use Pcore -role;

with qw[Pcore::API::Class];

requires qw[_build_file_api];

has file_api => ( is => 'lazy', isa => Str, init_arg => undef );

# EXT PANEL
sub ext_class_panel {
    my $self = shift;

    return $self->ext_define(
        'Pcore.tree.ExplorerPanel',
        {   treeRootId      => 0,
            treePanelType   => $self->ext_type( $self->ext_class( $self->get_api_obj( $self->file_api )->folder_api . '.Panel' ) ),
            viewPanelType   => $self->ext_type( $self->file_api . '.Panel' ),
            showBreadcrumb  => $TRUE,
            defaultViewType => 'small',

            canCreate      => $TRUE,
            canEdit        => $TRUE,
            canDelete      => $TRUE,
            selectCallback => undef,

            title => 'Uploads',
        }
    );
}

1;
__END__
=pod

=encoding utf8

=cut
