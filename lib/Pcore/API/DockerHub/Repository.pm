package Pcore::API::DockerHub::Repository;

use Pcore -class;
use Pcore::API::DockerHub qw[:CONST];
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
        splice @_, 1,
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
        splice @_, 1,
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
        splice @_, 1,
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/comments/?page_size=$args{page_size}&page=$args{page}", 1, undef, $args{cb} );
}

# STAR
sub star_repo ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    return $self->api->request( 'post', "/repositories/@{[$self->id]}/stars/", 1, {}, $args{cb} );
}

sub unstar_repo ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    return $self->api->request( 'delete', "/repositories/@{[$self->id]}/stars/", 1, undef, $args{cb} );
}

# WEBHOOK
sub webhooks ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1,
    );

    return $self->api->request(
        'get',
        "/repositories/@{[$self->id]}/webhooks/?page_size=$args{page_size}&page=$args{page}",
        1, undef,
        sub($res) {
            if ( $res->is_success ) {
                $res->{count} = delete $res->{result}->{count};

                $res->{next} = delete $res->{result}->{next};

                $res->{previous} = delete $res->{result}->{previous};

                my $result = {};

                for my $webhook ( $res->{result}->{results}->@* ) {
                    $webhook = bless $webhook, 'Pcore::API::DockerHub::Repository::WebHook';

                    $webhook->{status} = $res->status;

                    $webhook->{repo} = $self;

                    $result->{ $webhook->{name} } = $webhook;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub create_webhook ( $self, $webhook_name, $url, % ) {
    my %args = (
        cb => undef,
        splice @_, 3,
    );

    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->api->request(
        'post',
        "/repositories/@{[$self->id]}/webhooks/",
        1,
        { name => $webhook_name },
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 201;

            if ( !$res->is_success ) {
                $args{cb}->($res) if $args{cb};

                $blocking_cv->send($res) if $blocking_cv;
            }
            else {
                # create webhook object
                my $webhook = bless $res->{result}, 'Pcore::API::DockerHub::Repository::WebHook';

                $webhook->{status} = $res->status;

                $webhook->{repo} = $self;

                # create webhook hook
                $self->api->request(
                    'post',
                    "/repositories/@{[$self->id]}/webhooks/@{[$res->{result}->{id}]}/hooks/",
                    1,
                    { hook_url => $url },
                    sub ($hook_res) {
                        $hook_res->{status} = 200 if $hook_res->{status} == 201;

                        # roll back transaction if request is not successfull
                        if ( !$hook_res->is_success ) {
                            $webhook->remove(
                                cb => sub ($res) {
                                    $args{cb}->($hook_res) if $args{cb};

                                    $blocking_cv->send($hook_res) if $blocking_cv;

                                    return;
                                }
                            );
                        }
                        else {
                            push $webhook->{hooks}->@*, $hook_res->{result};

                            $args{cb}->($webhook) if $args{cb};

                            $blocking_cv->send($webhook) if $blocking_cv;
                        }

                        return;
                    }
                );
            }

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub remove_empty_webhooks ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->webhooks(
        cb => sub ($res) {
            my $cv = AE::cv sub {
                $args{cb}->($res) if $args{cb};

                $blocking_cv->send($res) if $blocking_cv;

                return;
            };

            $cv->begin;

            if ( $res->{result}->%* ) {
                for my $webhook ( values $res->{result}->%* ) {
                    if ( !$webhook->{hooks}->@* ) {
                        $cv->begin;

                        $webhook->remove(
                            cb => sub ($res) {
                                $cv->end;

                                return;
                            }
                        );
                    }
                }
            }

            $cv->end;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# BUILD LINKS
sub links ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    return $self->api->request(
        'get',
        "/repositories/@{[$self->id]}/links/",
        1, undef,
        sub($res) {
            if ( $res->is_success ) {
                $res->{count} = delete $res->{result}->{count};

                $res->{next} = delete $res->{result}->{next};

                $res->{previous} = delete $res->{result}->{previous};

                my $result = {};

                for my $link ( $res->{result}->{results}->@* ) {
                    $link = bless $link, 'Pcore::API::DockerHub::Repository::Link';

                    $link->{status} = $res->status;

                    $link->{repo} = $self;

                    $result->{ $link->id } = $link;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub create_link ( $self, $to_repo, % ) {
    my %args = (
        cb => undef,
        splice @_, 2,
    );

    $to_repo = "library/$to_repo" if $to_repo !~ m[/]sm;

    return $self->api->request(
        'post',
        "/repositories/@{[$self->id]}/links/",
        1,
        { to_repo => $to_repo },
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 201;

            if ( $res->is_success ) {
                my $link = bless $res->{result}, 'Pcore::API::DockerHub::Repository::Link';

                $link->{status} = $res->status;

                $link->{reason} = $res->reason;

                $link->{repo} = $self;

                $_[0] = $link;

                $res = $link;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# BUILD TRIGGER
sub build_trigger ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/buildtrigger/", 1, undef, $args{cb} );
}

sub build_trigger_history ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/buildtrigger/history", 1, undef, $args{cb} );
}

# BUILD
# NOTE build tag MUST be created before buid will be triggered
sub trigger_build ( $self, $source_type = $DOCKERHUB_SOURCE_TAG, $source_name = 'latest', % ) {
    my %args = (
        cb                  => undef,
        dockerfile_location => q[/],
        splice @_, 3,
    );

    return $self->api->request(
        'post',
        "/repositories/@{[$self->id]}/autobuild/trigger-build/",
        1,
        {   source_type         => $Pcore::API::DockerHub::DOCKERHUB_SOURCE_NAME->{$source_type},
            source_name         => $source_name,
            dockerfile_location => $args{dockerfile_location},
        },
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 202;

            if ( $res->{status} == 200 && !$res->{result}->@* ) {
                $res->{status} = 404;

                $res->{reason} = 'Invalid build source name';
            }
            else {
                my $result = {};

                for my $build ( $res->{result}->@* ) {
                    $build = bless $build, 'Pcore::API::DockerHub::Repository::Build';

                    $build->{status} = $res->status;

                    $build->{repo} = $self;

                    $result->{ $build->{build_code} } = $build;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub build_history ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1,
    );

    return $self->api->request(
        'get',
        "/repositories/@{[$self->id]}/buildhistory/?page_size=$args{page_size}&page=$args{page}",
        1, undef,
        sub ($res) {
            if ( $res->is_success ) {
                $res->{count} = delete $res->{result}->{count};

                $res->{next} = delete $res->{result}->{next};

                $res->{previous} = delete $res->{result}->{previous};

                my $result = [];

                for my $build ( $res->{result}->{results}->@* ) {
                    $build = bless $build, 'Pcore::API::DockerHub::Repository::Build';

                    $build->{status} = $res->status;

                    $build->{repo} = $self;

                    push $result->@*, $build;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# only for automated builds
sub build_settings ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
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
        name                => '{sourceref}',            # docker build tag name
        source_type         => $DOCKERHUB_SOURCE_TAG,    # Branch, Tag
        source_name         => '/.*/',                   # barnch / tag name in the source repository
        dockerfile_location => q[/],
        splice @_, 1,
    );

    return $self->api->request(
        'post',
        "/repositories/@{[$self->id]}/autobuild/tags/",
        1,
        {   name                => $args{name},
            source_type         => $Pcore::API::DockerHub::DOCKERHUB_SOURCE_NAME->{ $args{source_type} },
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

# REPO TAGS
sub tags ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1,
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
        splice @_, 1,
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

                    $result->{ $collaborator->{user} } = $collaborator;
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
        splice @_, 2,
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
        splice @_, 1,
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
## │    3 │ 235, 236             │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 359                  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
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
