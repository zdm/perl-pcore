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
sub links ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/links/", 1, undef, $args{cb} );
}

sub create_link ( $self, $to_repo, % ) {
    my %args = (
        cb => undef,
        splice @_, 2
    );

    $to_repo = "library/$to_repo" if $to_repo !~ m[/]sm;

    return $self->api->request( 'post', "/repositories/@{[$self->id]}/links/", 1, { to_repo => $to_repo }, $args{cb} );
}

# BUILD TRIGGER
sub trigger ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/buildtrigger/", 1, undef, $args{cb} );
}

sub trigger_history ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/buildtrigger/history", 1, undef, $args{cb} );
}

# BUILD
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

sub get_build_history ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        cb        => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/buildhistory/?page_size=$args{page_size}&page=$args{page}", 1, undef, $args{cb} );
}

sub get_build_settings ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/autobuild/", 1, undef, $args{cb} );
}

# BUILD TAG
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
        "/repositories/@{[$self->id]}/autobuilds/tags/",
        1,
        {   name                => $args{name},
            source_type         => $args{source_type},
            source_name         => $args{source_name},
            dockerfile_location => $args{dockerfile_location},
        },
        $args{cb}
    );
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

# COLLABORATORS
sub collaborators ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->api->request( 'get', "/repositories/@{[$self->id]}/collaborators/", 1, undef, $args{cb} );
}

sub create_collaborator ( $self, $collaborator_name, % ) {
    my %args = (
        cb => undef,
        splice @_, 2
    );

    return $self->api->request( 'post', "/repositories/@{[$self->id]}/collaborators/", 1, { user => $collaborator_name }, $args{cb} );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 182                  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 185, 228             │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 32, 52, 72, 84, 93,  │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## │      │ 104, 133, 143, 152,  │                                                                                                                │
## │      │ 164, 173, 183, 202,  │                                                                                                                │
## │      │ 213, 223, 247, 260,  │                                                                                                                │
## │      │ 269                  │                                                                                                                │
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
