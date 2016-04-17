package Pcore::API::Class::Upload::Folder;

use Pcore -role;

with qw[Pcore::API::Class::Tree];

requires qw[_build_root];

has root => ( is => 'lazy', isa => Str, init_arg => undef );

our $FIELDS = {

    # TODO validators => [ { type => 'presence' }, { type => 'filename' } ]
    text => { type => 'str', isa_type => FileNameStr, persist => 'rw' },
};

around APP_BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig;

    {
        my $sql = q[
            ALTER TABLE ] . $self->dbh->quote_id( $self->table ) . q[
                ADD UNIQUE INDEX IF NOT EXISTS `parent_id_text` (`parent_id`,`text`)
            ;
            ];

        $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES]] );
    }

    return;
};

around BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig(@_);

    $self->add_fields($FIELDS);

    return;
};

around ext_class_panel => sub {
    my $orig = shift;
    my $self = shift;

    return $self->$orig->apply( { title => 'Folders' } );
};

# API UPDATE
# TODO implement move node
sub on_api_update_read_record {
    my $self = shift;
    my $rec  = shift;

    if ( exists $rec->in_fields->{parent_id} || exists $rec->in_fields->{text} ) {

        # read and cache original row
        my ( $sql, @bind ) = $self->sqla->select(
            -columns => [ 'id', 'parent_id', 'text' ],
            -from    => $self->table,
            -where => { id => $rec->id }
        );

        if ( my $orig_rec = $self->dbh->selectrow( $sql, {}, @bind ) ) {

            # TODO implement move node
            $self->exception(q[Moving node not supported yet]) if exists $rec->in_fields->{parent_id} && $orig_rec->{parent_id} != $rec->in_fields->{parent_id};

            # cache original record
            $rec->set_orig_record($orig_rec);
        }
        else {
            $self->exception( q[Can't update id = "] . $rec->id . q["] );
        }
    }

    return;
}

sub on_api_update_write_record {
    my $self = shift;
    my $rec  = shift;

    # folder name was changed, need to move folder to the new location
    if ( $rec->has_orig_fields && $rec->out_fields->{text} ne $rec->orig_fields->{text} ) {
        my $parent_path = $self->root . $self->get_path( $rec->out_fields->{parent_id} );

        my $old_path = $parent_path . $rec->orig_fields->{text};
        my $new_path = $parent_path . $rec->out_fields->{text};

        P->file->move( $old_path, $new_path );
    }

    return;
}

# API DESTROY
sub on_api_destroy_read_record {
    my $self = shift;
    my $rec  = shift;

    my $path = $self->get_path( $rec->id );

    return if !$path;

    $rec->set_orig_record( { path => $self->root . $path } );

    return;
}

sub on_api_destroy_write_record {
    my $self = shift;
    my $rec  = shift;

    P->file->rmtree( $rec->orig_fields->{path} ) if $rec->has_orig_fields;

    return;
}

# UTIL
sub get_path {
    my $self = shift;
    my $id   = shift;

    my $cache = $self->call_cache->{folder_path} //= {};

    if ( !exists $cache->{$id} ) {
        if ( my $res = $self->db_get_parent_nodes($id) ) {
            $cache->{$id} = join( q[/], map { $_->{text} } $res->@* ) . q[/];
        }
        else {
            $cache->{$id} = q[];
        }
    }

    return $cache->{$id};
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 24, 25               | ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
