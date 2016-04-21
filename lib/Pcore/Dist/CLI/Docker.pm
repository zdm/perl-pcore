package Pcore::Dist::CLI::Docker;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'manage docker repository',
        opt      => {
            trigger => {
                desc => 'trigger tag build',
                type => 'TAG',
                isa  => 'Str',
            },
            remove => {
                desc => 'remove tag',
                type => 'TAG',
                isa  => 'Str',
            },
        },
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    $self->new->run($opt);

    return;
}

sub run ( $self, $args ) {
    if ( !$self->dist->build->docker ) {
        my $namespace = $ENV->user_cfg->{'Pcore::API::DockerHub'}->{namespace} || $ENV->user_cfg->{'Pcore::API::DockerHub'}->{api_username};

        if ( !$namespace ) {
            say 'DockerHub namespace is not defined';

            exit 3;
        }

        my $repo_name = lc $self->dist->name;

        my $confirm = P->term->prompt( qq[Create DockerHub repository "$namespace/$repo_name"?], [qw[yes no]], enter => 1 );

        if ( $confirm eq 'no' ) {
            exit 3;
        }

        require Pcore::API::DockerHub;

        my $api = Pcore::API::DockerHub->new( { namespace => $namespace } );

        my $upstream = $self->dist->scm->upstream;

        print q[Creating DockerHub repository ... ];

        my $res = $api->create_automated_build(    #
            $repo_name, $upstream->hosting == $Pcore::API::SCM::Upstream::SCM_HOSTING_BITBUCKET ? $Pcore::API::DockerHub::DOCKERHUB_PROVIDER_BITBUCKET : $Pcore::API::DockerHub::DOCKERHUB_PROVIDER_GITHUB,
            "@{[$upstream->namespace]}/@{[$upstream->repo_name]}",
            $self->dist->module->abstract || $self->dist->name,
            private => 0,
            active  => 1
        );

        say $res->reason;

        if ( !$res->is_success ) {
            exit 3;
        }
        else {
            require Pcore::Util::File::Tree;

            # copy files
            my $files = Pcore::Util::File::Tree->new;

            $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) . '/docker/' );

            $files->add_file( 'share/docker.json', P->data->to_json( { namespace => $namespace }, readable => 1 ) );

            $files->render_tmpl(
                {   pcore_dockerhub_namespace => $ENV->pcore->docker_cfg->{namespace},
                    author                    => $self->dist->cfg->{dist}->{author},
                    dist_path                 => lc $self->dist->name,
                }
            );

            $files->write_to( $self->dist->root );
        }
    }
    else {
        $self->dist->build->docker->run($args);
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 91                   | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Docker - manage docker repository

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
