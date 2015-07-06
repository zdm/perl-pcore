package Dist::Zilla::Plugin::Pcore::MintFiles;

use Moose;
use Pcore;
use Dist::Zilla::File::InMemory;

with qw[Dist::Zilla::Role::BeforeMint Dist::Zilla::Role::FileGatherer];

has tmpl_params => ( is => 'ro', isa => 'HashRef', lazy => 1, builder => '_build_tmpl_params', init_arg => undef );

no Pcore;
no Moose;

sub _build_tmpl_params ($self) {
    return {
        dist_name          => $self->zilla->name,
        dist_path          => lc $self->zilla->name,
        module_name        => $self->zilla->name =~ s[-][::]smgr,
        module_path        => $self->zilla->name =~ s[-][/]smgr,
        main_script        => 'main.pl',
        author             => $self->zilla->stash_named('%User')->{'name'},
        author_email       => $self->zilla->stash_named('%User')->{'email'},
        copyright_year     => P->date->now->year,
        copyright_holder   => $self->zilla->stash_named('%Rights')->{'copyright_holder'},
        license            => $self->zilla->stash_named('%Rights')->{'license_class'},
        bitbucket_username => $self->zilla->stash_named('%Pcore::Bitbucket') ? $self->zilla->stash_named('%Pcore::Bitbucket')->username : 'username',
        dockerhub_username => $self->zilla->stash_named('%Pcore::DockerHub') ? $self->zilla->stash_named('%Pcore::DockerHub')->username : 'username',
    };
}

sub before_mint ($self) {
    return;
}

sub gather_files ($self) {
    my $chdir_guard = P->file->chdir(q[tmpl]);

    my $tmpl = P->tmpl;

    P->file->find(
        {   wanted => sub {
                return if -d;

                my $content = P->file->read_bin($_);

                $self->add_file(
                    Dist::Zilla::File::InMemory->new(
                        {   name    => $_,
                            content => $tmpl->render( $content, $self->tmpl_params )->$*,
                        }
                    ),
                );
            },
            no_chdir => 1,
        },
        q[.]
    );

    return;
}

sub make_module ( $self, @ ) {
    my $tmpl = P->tmpl;

    my $content = P->file->read_bin('Module.pm');

    $self->add_file(
        Dist::Zilla::File::InMemory->new(
            {   name    => 'lib/' . $self->tmpl_params->{module_path} . '.pm',
                content => $tmpl->render( $content, $self->tmpl_params )->$*,
            }
        ),
    );

    return;
}

__PACKAGE__->meta->make_immutable;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Dist::Zilla::Plugin::Pcore::MintFiles

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
