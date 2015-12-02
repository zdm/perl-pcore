package Pcore::Dist::Build::Files::File;

use Pcore qw[-class];

has path => ( is => 'ro', isa => Str, required => 1 );    # relative file path, mandatory
has source_path => ( is => 'ro', isa => Str );                                # absolute source path
has content => ( is => 'lazy', isa => Maybe [ScalarRef], predicate => 1 );    # content ref

no Pcore;

sub _build_content ($self) {
    if ( $self->source_path && -f $self->source_path ) {
        return P->file->read_bin( $self->source_path );
    }

    return;
}

sub write_to ( $self, $target_path ) {
    $target_path = P->path( $target_path . q[/] . $self->path );

    if ( $self->has_content ) {
        P->file->mkpath( $target_path->dirname );

        P->file->write_bin( $target_path, $self->content );
    }
    elsif ( $self->source_path ) {
        P->file->mkpath( $target_path->dirname );

        P->file->copy( $self->source_path, $target_path );
    }

    return;
}

sub render_tmpl ( $self, $tmpl_args ) {
    my $tmpl = P->tmpl;

    $self->{content} = $tmpl->render( $self->content, $tmpl_args );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Files::File

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
