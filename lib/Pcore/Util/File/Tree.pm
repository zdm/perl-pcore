package Pcore::Util::File::Tree;

use Pcore qw[-class];
use Pcore::Util::File::Tree::File;

has files => ( is => 'lazy', isa => HashRef [ InstanceOf ['Pcore::Util::File::Tree::File'] ], default => sub { {} }, init_arg => undef );

no Pcore;

sub add_dir ( $self, $dir, $root = undef ) {
    $dir = P->path( $dir, is_dir => 1 )->realpath->to_string;

    my $files = $self->files;

    my $chdir_guard = P->file->chdir($dir);

    P->file->find(
        q[.],
        dir => 0,
        sub ($path) {
            $self->add_file( ( $root // q[] ) . $path->to_string, $dir . $path );

            return;
        },
    );

    return;
}

sub add_file ( $self, $path, $source ) {
    my $file;

    if ( ref $source eq 'SCALAR' ) {
        $file = Pcore::Util::File::Tree::File->new( { tree => $self, path => $path, content => $source } );
    }
    else {
        $file = Pcore::Util::File::Tree::File->new( { tree => $self, path => $path, source_path => $source } );
    }

    $self->files->{$path} = $file;

    return $file;
}

sub remove_file ( $self, $path ) {
    delete $self->files->{$path};

    return;
}

sub move_file ( $self, $path, $target_path ) {
    if ( my $file = delete $self->files->{$path} ) {
        $file->{path} = $target_path;

        $self->files->{$target_path} = $file;
    }

    return;
}

sub find_file ( $self, $cb ) {
    for my $file ( values $self->files->%* ) {
        $cb->($file);
    }

    return;
}

sub render_tmpl ( $self, $tmpl_args ) {
    for my $file ( values $self->files->%* ) {
        $file->render_tmpl($tmpl_args);
    }

    return;
}

sub write_to ( $self, $target_path, @ ) {
    my %args = (
        manifest => undef,
        @_[ 2 .. $#_ ],
    );

    for my $file ( values $self->files->%* ) {
        $file->write_to($target_path);
    }

    # write MANIFEST
    P->file->write_bin( $target_path . q[/MANIFEST], [ sort 'MANIFEST', keys $self->files->%* ] ) if $args{manifest};

    return;
}

sub write_to_temp ( $self, @ ) {
    my %args = (
        base     => undef,
        tmpl     => undef,
        manifest => undef,
        @_[ 1 .. $#_ ],
    );

    my $tempdir = P->file->tempdir(    #
        ( $args{base} ? ( base => $args{base} ) : () ),
        ( $args{tmpl} ? ( tmpl => $args{tmpl} ) : () ),
    );

    $self->write_to( $tempdir, manifest => $args{manifest} );

    return $tempdir;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 62, 70, 83, 88       │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File::Tree

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
