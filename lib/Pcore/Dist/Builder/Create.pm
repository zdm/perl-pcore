package Pcore::Dist::Builder::Create;

use Pcore qw[-class];
use Pcore::Dist;
use Pcore::Dist::BuilderUtil::Files;

with qw[Pcore::Core::CLI::Cmd Pcore::Dist::BuilderUtil];

has namespace => ( is => 'ro', isa => Str,  required => 1 );    # Dist::Name
has cpan      => ( is => 'ro', isa => Bool, default  => 0 );

has path => ( is => 'lazy', init_arg => undef );                          # /absolute/path/to/dist-name/
has tmpl_params => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

# CLI
sub cli_name ($self) {
    return 'new';
}

sub cli_opt ($self) {
    return {
        cpan => {
            desc     => 'create CPAN distribution',
            negated  => 1,
            required => 1,
            default  => 0,
        },
    };
}

sub cli_arg ($self) {
    return [    #
        {   name     => 'namespace',
            type     => 'Str',
            required => 1,
        },
    ];
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $opt->{namespace} = $arg->{namespace};

    $self->new($opt)->run;

    return;
}

# BUILDERS
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
        dist_name          => $self->namespace =~ s/::/-/smgr,                                                              # Package-Name
        dist_path          => lc $self->namespace =~ s/::/-/smgr,                                                           # package-name
        module_name        => $self->namespace,                                                                             # Package::Name
        main_script        => 'main.pl',
        author             => Pcore::Dist->global_cfg->{_}->{author},
        author_email       => Pcore::Dist->global_cfg->{_}->{email},
        copyright_year     => P->date->now->year,
        copyright_holder   => Pcore::Dist->global_cfg->{_}->{copyright_holder} || Pcore::Dist->global_cfg->{_}->{author},
        license            => Pcore::Dist->global_cfg->{_}->{license},
        bitbucket_username => Pcore::Dist->global_cfg->{Bitbucket}->{username} // 'username',
        dockerhub_username => Pcore::Dist->global_cfg->{DockerHub}->{username} // 'username',
        cpan_distribution  => $self->cpan,
    };
}

# TODO update dist after create
sub run ($self) {
    $self->quit('pcore.ini not found') if !Pcore::Dist->global_cfg;

    my $path = $self->path;

    $self->quit('Path already exists') if !$path;

    my $files = Pcore::Dist::BuilderUtil::Files->new( $PROC->res->get_storage( 'pcore', 'pcore' ) );

    $files->rename_file( 'lib/Module.pm', 'lib/' . $self->namespace =~ s[::][/]smgr . '.pm' );

    $files->render_tmpl( $self->tmpl_params );

    $files->write_to($path);

    my $dist = Pcore::Dist->new($path);

    # TODO update dist after create

    return $dist;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Builder::Create - create new distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
