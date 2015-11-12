package Pcore::Dist::Create;

use Pcore qw[-class];

with qw[Pcore::Dist::Config Pcore::Dist::Log];

has namespace => ( is => 'ro', isa => Str, required => 1 );    # Dist::Name

has path => ( is => 'lazy', init_arg => undef );                          # /absolute/path/to/dist-name/
has tmpl_params => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

sub _build_path ($self) {
    my $path = P->path( lc $self->namespace =~ s/::/-/smgr, is_dir => 1 );

    if ( -e $path ) {
        return;
    }
    else {
        P->file->mkpath($path);

        return $path->realpath;
    }
}

sub _build_tmpl_params ($self) {
    return {
        dist_name          => $self->namespace =~ s/::/-/smgr,
        dist_path          => lc $self->namespace =~ s/::/-/smgr,
        module_name        => $self->namespace,
        module_path        => $self->namespace =~ s[::][/]smgr,
        main_script        => 'main.pl',
        author             => $self->user_cfg->{_}->{username},
        author_email       => $self->user_cfg->{_}->{email},
        copyright_year     => P->date->now->year,
        copyright_holder   => $self->user_cfg->{_}->{copyright_holder},
        license            => $self->user_cfg->{_}->{license},
        bitbucket_username => $self->user_cfg->{Bitbucket}->{username} // 'username',
        dockerhub_username => $self->user_cfg->{DockerHub}->{username} // 'username',
    };
}

sub create ($self) {
    $self->quit('pcore.ini not found') if !$self->user_cfg;

    my $path = $self->path;

    $self->quit('Path already exists') if !$path;

    $self->gather_files;

    $self->make_main_module;

    return $path;
}

sub gather_files ($self) {
    my $chdir_guard = P->file->chdir( $P->{SHARE_DIR} . 'pcore/dist/' );

    my $tmpl = P->tmpl;

    P->file->find(
        {   wanted => sub {
                return if -d;

                my $content = $tmpl->render( P->file->read_bin($_), $self->tmpl_params )->$*;

                my $target_path = P->path( $self->path . $_ );

                P->file->mkpath( $target_path->dirname );

                P->file->write_bin( $target_path, $content );
            },
            no_chdir => 1,
        },
        q[.]
    );

    return;
}

sub make_main_module ( $self, @ ) {
    my $tmpl = P->tmpl;

    my $content = $tmpl->render( P->file->read_bin( $P->{SHARE_DIR} . 'pcore/Module.pm' ), $self->tmpl_params );

    my $target_path = P->path( $self->path . 'lib/' . $self->namespace =~ s[::][/]smgr . '.pm' );

    P->file->mkpath( $target_path->dirname );

    P->file->write_bin( $target_path, $content );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Create

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
