package Pcore::API::DockerHub::Repository;

use Pcore -class;
use Pcore::API::DockerHub::Repository::WebHook;
use Pcore::API::DockerHub::Repository::Link;
use Pcore::API::DockerHub::Repository::Build;
use Pcore::API::DockerHub::Repository::Tag;
use Pcore::API::DockerHub::Repository::Build::Tag;
use Pcore::API::DockerHub::Repository::Collaborator;

extends qw[Pcore::API::Response];

has api => ( is => 'ro', isa => InstanceOf ['Pcore::API::DockerHub'], required => 1 );

has name      => ( is => 'lazy', isa => Str, init_arg => undef );
has namespace => ( is => 'lazy', isa => Str, init_arg => undef );
has id        => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_name ($self) {
    return $self->{name};
}

sub _build_namespace ($self) {
    return $self->{namespace};
}

sub _build_id ($self) {
    return $self->namespace . q[/] . $self->name;
}

sub remove ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request(
        'delete',
        "/repositories/@{[$self->id]}/",
        1, undef,
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 202;

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub set_desc ( $self, % ) {
    my %args = (
        cb        => undef,
        desc      => undef,
        desc_full => undef,
        splice @_, 1
    );

    return $self->api->request(
        'patch',
        "/repositories/@{[$self->id]}/",
        1,
        {   description      => $args{desc},
            description_full => $args{desc_full},
        },
        $args{cb}
    );
}

# COMMENTS
sub comments ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/comments/?page_size=$args{page_size}&page=$args{page}", 1, undef, $args{cb} );
}

# STAR
sub star_repo ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'post', "/repositories/@{[$self->id]}/stars/", 1, {}, $args{cb} );
}

sub unstar_repo ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'delete', "/repositories/@{[$self->id]}/stars/", 1, undef, $args{cb} );
}

# WEBHOOK
# TODO
sub webhooks ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1
    );

    return $self->api->request(
        'get',
        "/repositories/@{[$self->id]}/webhooks/?page_size=$args{page_size}&page=$args{page}",
        1, undef,
        sub ($res) {
            if ( $res->is_success ) {
                for my $webhook ( $res->{result}->{results}->@* ) {
                    my $repo = bless $res->{result}, 'Pcore::API::DockerHub::Repository::WebHook';

                    $repo->{api} = $self;
                }
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# TODO
sub create_webhook ( $self, $webhook_name, % ) {
    my %args = (
        cb => undef,
        splice @_, 2
    );

    return $self->api->request( 'post', "/repositories/@{[$self->id]}/webhooks/", 1, { name => $webhook_name }, $args{cb} );
}

# BUILD LINK
# TODO
sub links ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/links/", 1, undef, $args{cb} );
}

# TODO
sub create_link ( $self, $to_repo, % ) {
    my %args = (
        cb => undef,
        splice @_, 2
    );

    $to_repo = "library/$to_repo" if $to_repo !~ m[/]sm;

    return $self->api->request( 'post', "/repositories/@{[$self->id]}/links/", 1, { to_repo => $to_repo }, $args{cb} );
}

# BUILD TRIGGER
sub build_trigger ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/buildtrigger/", 1, undef, $args{cb} );
}

sub build_trigger_history ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/buildtrigger/history", 1, undef, $args{cb} );
}

# BUILD
# TODO
sub trigger_build ( $self, $source_type = 'Tag', $source_name = 'latest', % ) {
    my %args = (
        cb                  => undef,
        dockerfile_location => '/',
        splice @_, 3
    );

    return $self->api->request(
        'post',
        "/repositories/@{[$self->id]}/autobuild/trigger-build/",
        1,
        {   source_type         => $source_type,
            source_name         => $source_name,
            dockerfile_location => $args{dockerfile_location},
        },
        $args{cb}
    );
}

sub build_history ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/buildhistory/?page_size=$args{page_size}&page=$args{page}", 1, undef, $args{cb} );
}

# only for automated builds
sub build_settings ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request(
        'get',
        "/repositories/@{[$self->id]}/autobuild/",
        1, undef,
        sub ($res) {
            if ( $res->is_success ) {
                my $build_tags = {};

                for my $build_tag ( $res->{result}->{build_tags}->@* ) {
                    my $tag = bless $build_tag, 'Pcore::API::DockerHub::Repository::Build::Tag';

                    $tag->{repo} = $self;

                    $build_tags->{ $tag->id } = $tag;
                }

                $res->{result}->{build_tags} = $build_tags;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# only for automated builds
sub create_build_tag ( $self, % ) {
    my %args = (
        cb                  => undef,
        name                => '{sourceref}',    # docker build tag name
        source_type         => 'Tag',            # Branch, Tag
        source_name         => '/.*/',           # barnch / tag name in the source repository
        dockerfile_location => '/',
        splice @_, 1
    );

    return $self->api->request(
        'post',
        "/repositories/@{[$self->id]}/autobuild/tags/",
        1,
        {   name                => $args{name},
            source_type         => $args{source_type},
            source_name         => $args{source_name},
            dockerfile_location => $args{dockerfile_location},
        },
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 201;

            if ( $res->is_success ) {
                my $tag = bless $res->{result}, 'Pcore::API::DockerHub::Repository::Build::Tag';

                $tag->{status} = $res->status;

                $tag->{reason} = $res->reason;

                $tag->{repo} = $self;

                $_[0] = $tag;

                $res = $tag;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# REPO TAG
sub tags ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1
    );

    return $self->api->request(
        'get',
        "/repositories/@{[$self->id]}/tags/?page_size=$args{page_size}&page=$args{page}",
        1, undef,
        sub($res) {
            if ( $res->is_success ) {
                $res->{count} = delete $res->{result}->{count};

                $res->{next} = delete $res->{result}->{next};

                $res->{previous} = delete $res->{result}->{previous};

                my $result = {};

                for my $repo ( $res->{result}->{results}->@* ) {
                    $repo = bless $repo, 'Pcore::API::DockerHub::Repository::Tag';

                    $repo->{status} = $res->status;

                    $repo->{repo} = $self;

                    $result->{ $repo->id } = $repo;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# COLLABORATORS
# only for user repositories
sub collaborators ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request(
        'get',
        "/repositories/@{[$self->id]}/collaborators/",
        1, undef,
        sub($res) {
            if ( $res->is_success ) {
                $res->{count} = delete $res->{result}->{count};

                $res->{next} = delete $res->{result}->{next};

                $res->{previous} = delete $res->{result}->{previous};

                my $result = {};

                for my $collaborator ( $res->{result}->{results}->@* ) {
                    $collaborator = bless $collaborator, 'Pcore::API::DockerHub::Repository::Collaborator';

                    $collaborator->{status} = $res->status;

                    $collaborator->{repo} = $self;

                    $result->{ $collaborator->id } = $collaborator;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub create_collaborator ( $self, $collaborator_name, % ) {
    my %args = (
        cb => undef,
        splice @_, 2
    );

    return $self->api->request(
        'post',
        "/repositories/@{[$self->id]}/collaborators/",
        1,
        { user => $collaborator_name },
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 201;

            if ( $res->is_success ) {
                my $collaborator = bless $res->{result}, 'Pcore::API::DockerHub::Repository::Collaborator';

                $collaborator->{status} = $res->status;

                $collaborator->{reason} = $res->reason;

                $collaborator->{repo} = $self;

                $_[0] = $collaborator;

                $res = $collaborator;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# GROUPS
# only for organization repository
sub groups ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/groups/", 1, undef, $args{cb} );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 185                  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 188, 255             │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 32, 52, 72, 84, 93,  │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## │      │ 104, 133, 144, 154,  │                                                                                                                │
## │      │ 166, 175, 186, 205,  │                                                                                                                │
## │      │ 217, 250, 294, 338,  │                                                                                                                │
## │      │ 378, 415             │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::DockerHub::Repository

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
