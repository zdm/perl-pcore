package Pcore::Dist::CLI::Docker;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return { abstract => 'manage docker repository', };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    $self->new->run($opt);

    return;
}

sub run ( $self, $args ) {
    if ( !$self->dist->cfg->{docker_namespace} ) {
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

        }
    }

    return;
}

1;
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
