package Pcore::API::DockerHub::Repository;

use Pcore -class;
use Pcore::API::DockerHub::Repository::WebHook;

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

    return $self->api->_request(
        'delete',
        "/repositories/$self->{owner}/$self->{name}/",
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

    return $self->api->_request(
        'patch',
        "/repositories/$self->{owner}/$self->{name}/",
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

    return $self->api->_request( 'get', "/repositories/$self->{owner}/$self->{name}/comments/?page_size=$args{page_size}&page=$args{page}", 1, undef, $args{cb} );
}

# STAR
sub star_repo ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->_request( 'post', "/repositories/$self->{owner}/$self->{name}/stars/", 1, {}, $args{cb} );
}

sub unstar_repo ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->_request( 'delete', "/repositories/$self->{owner}/$self->{name}/stars/", 1, undef, $args{cb} );
}

# WEBHOOK
sub webhooks ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1
    );

    return $self->api->_request(
        'get',
        "/repositories/@{[$self->path]}/webhooks/?page_size=$args{page_size}&page=$args{page}",
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

sub create_webhook ( $self, $webhook_name, % ) {
    my %args = (
        cb => undef,
        splice @_, 2
    );

    return $self->api->_request( 'post', "/repositories/$self->{owner}/$self->{name}/webhooks/", 1, { name => $webhook_name }, $args{cb} );
}

# BUILD LINK
sub create_build_link ( $self, $repo_name, $to_repo, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    $to_repo = "library/$to_repo" if $to_repo !~ m[/]sm;

    return $self->_request( 'post', "/repositories/$args{repo_owner}/$repo_name/links/", 1, { to_repo => $to_repo }, $args{cb} );
}

sub get_build_links ( $self, $repo_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/links/", 1, undef, $args{cb} );
}

sub delete_build_link ( $self, $repo_name, $build_link_id, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'delete', "/repositories/$args{repo_owner}/$repo_name/links/$build_link_id/", 1, undef, $args{cb} );
}

# BUILD TRIGGER
sub get_build_trigger ( $self, $repo_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/buildtrigger/", 1, undef, $args{cb} );
}

sub get_build_trigger_history ( $self, $repo_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/buildtrigger/history", 1, undef, $args{cb} );
}

# BUILD
sub trigger_build ( $self, $repo_name, $source_type = 'Tag', $source_name = 'latest', % ) {
    my %args = (
        repo_owner          => $self->username,
        cb                  => undef,
        dockerfile_location => '/',
        splice @_, 4
    );

    return $self->_request(
        'post',
        "/repositories/$args{repo_owner}/$repo_name/autobuild/trigger-build/",
        1,
        {   source_type         => $source_type,
            source_name         => $source_name,
            dockerfile_location => $args{dockerfile_location},
        },
        $args{cb}
    );
}

sub get_build_details ( $self, $repo_name, $build_id, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/buildhistory/$build_id/", 1, undef, $args{cb} );
}

sub get_build_history ( $self, $repo_name, % ) {
    my %args = (
        page       => 1,
        page_size  => 100,
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/buildhistory/?page_size=$args{page_size}&page=$args{page}", 1, undef, $args{cb} );
}

sub get_build_settings ( $self, $repo_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/autobuild/", 1, undef, $args{cb} );
}

# BUILD TAG
sub create_build_tag ( $self, $repo_name, % ) {
    my %args = (
        repo_owner          => $self->username,
        cb                  => undef,
        name                => '{sourceref}',     # docker build tag name
        source_type         => 'Tag',             # Branch, Tag
        source_name         => '/.*/',            # barnch / tag name in the source repository
        dockerfile_location => '/',
        splice @_, 2
    );

    return $self->_request(
        'post',
        "/repositories/$args{repo_owner}/$repo_name/autobuilds/tags/",
        1,
        {   name                => $args{name},
            source_type         => $args{source_type},
            source_name         => $args{source_name},
            dockerfile_location => $args{dockerfile_location},
        },
        $args{cb}
    );
}

sub update_build_tag ( $self, $repo_name, $build_tag_id, % ) {
    my %args = (
        repo_owner          => $self->username,
        cb                  => undef,
        name                => '{sourceref}',     # docker build tag name
        source_type         => 'Tag',             # Branch, Tag
        source_name         => '/.*/',            # barnch / tag name in the source repository
        dockerfile_location => '/',
        splice @_, 3
    );

    return $self->_request(
        'put',
        "/repositories/$args{repo_owner}/$repo_name/autobuilds/tags/$build_tag_id/",
        1,
        {   id                  => $build_tag_id,
            name                => $args{name},
            source_type         => $args{source_type},
            source_name         => $args{source_name},
            dockerfile_location => $args{dockerfile_location},
        },
        $args{cb}
    );
}

sub delete_build_tag ( $self, $repo_name, $build_tag_id, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'delete', "/repositories/$args{repo_owner}/$repo_name/autobuild/tags/$build_tag_id/", 1, undef, $args{cb} );
}

# REPO TAG
sub get_tags ( $self, $repo_name, % ) {
    my %args = (
        page       => 1,
        page_size  => 100,
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/tags/?page_size=$args{page_size}&page=$args{page}", 1, undef, $args{cb} );
}

sub delete_tag ( $self, $repo_name, $tag_id, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'delete', "/repositories/$args{repo_owner}/$repo_name/tags/$tag_id/", 1, undef, $args{cb} );
}

# COLLABORATORS
sub create_collaborator ( $self, $repo_name, $collaborator_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'post', "/repositories/$args{repo_owner}/$repo_name/collaborators/", 1, { user => $collaborator_name }, $args{cb} );
}

sub get_collaborators ( $self, $repo_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/collaborators/", 1, undef, $args{cb} );
}

sub delete_collaborator ( $self, $repo_name, $collaborator_id, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'delete', "/repositories/$args{repo_owner}/$repo_name/collaborators/$collaborator_id/", 1, undef, $args{cb} );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 32, 54, 74, 84, 93,  │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## │      │ 105, 131             │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 135, 157, 189, 209,  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## │      │ 266, 291, 314, 325,  │                                                                                                                │
## │      │ 345                  │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 193, 249, 273        │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 27, 47, 67, 79, 88,  │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## │      │ 98, 126, 136, 148,   │                                                                                                                │
## │      │ 158, 169, 179, 190,  │                                                                                                                │
## │      │ 210, 220, 232, 243,  │                                                                                                                │
## │      │ 267, 292, 303, 315,  │                                                                                                                │
## │      │ 326, 336, 346        │                                                                                                                │
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
