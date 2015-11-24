package Pcore::Dist::BuilderUtil::Files;

use Pcore qw[-class];
use Pcore::Dist::BuilderUtil::Files::File;

has files => ( is => 'ro', isa => HashRef, required => 1 );

around new => sub ( $orig, $self, $source_path ) {
    $source_path = P->path( $source_path, is_dir => 1 )->realpath->to_string;

    my $files = {};

    my $chdir_guard = P->file->chdir($source_path);

    P->file->find(
        {   wanted => sub {
                return if -d;

                my $path = P->path($_);

                $files->{ $path->to_string } = Pcore::Dist::BuilderUtil::Files::File->new( { path => $path->to_string, source_path => $source_path . $path } );
            },
            no_chdir => 1,
        },
        q[.]
    );

    return $self->$orig( { files => $files } );
};

no Pcore;

sub add_file ( $self, $path, $content_ref ) {
    $self->files->{$path} = Pcore::Dist::BuilderUtil::Files::File->new( { path => $path, content => $content_ref } );

    return;
}

sub remove_file ( $self, $path ) {
    delete $self->files->{$path};

    return;
}

sub rename_file ( $self, $path, $target_path ) {
    if ( my $file = delete $self->files->{$path} ) {
        $file->{path} = $target_path;

        $self->files->{$target_path} = $file;
    }

    return;
}

sub write_to ( $self, $target_path, $write_manifest = 0 ) {
    for ( values $self->files->%* ) {
        $_->write_to($target_path);
    }

    # write MANIFEST
    P->file->write_bin( $target_path . q[/MANIFEST], [ sort 'MANIFEST', keys $self->files->%* ] ) if $write_manifest;

    return;
}

sub render_tmpl ( $self, $tmpl_args ) {
    for ( values $self->files->%* ) {
        $_->render_tmpl($tmpl_args);
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 56, 61, 67           │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::BuilderUtil::Files

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
