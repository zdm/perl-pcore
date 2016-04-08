package Pcore::API::DockerHub;

use Pcore -const, -class;
use Pcore::API::Response;

# https://github.com/RyanTheAllmighty/Docker-Hub-API.git

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

has login_token => ( is => 'ro', isa => Str, init_arg => undef );

const our $API_VERSION => 2;
const our $URL         => "https://hub.docker.com/v$API_VERSION";

sub login ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->_request(
        'post',
        '/users/login/',
        undef,
        { username => $self->username, password => $self->password },
        sub ($res) {
            if ( $res->{result}->{detail} ) {
                $res->{reason} = delete $res->{result}->{detail};
            }

            if ( $res->is_success && $res->{result}->{token} ) {
                $self->{login_token} = delete $res->{result}->{token};
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub get_user ( $self, % ) {
    my %args = (
        username => $self->username,
        cb       => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/users/$args{username}/", undef, undef, $args{cb} );
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

# CREATE REPO / AUTOMATED BUILD
sub create_repo ( $self, $repo_name, % ) {
    my %args = (
        repo_owner => $self->username,
        private    => 0,
        desc       => '',
        full_desc  => '',
        cb         => undef,
        splice @_, 2
    );

    return $self->_request(
        'post',
        '/repositories/',
        1,
        {   name             => $repo_name,
            namespace        => $args{repo_owner},
            is_private       => $args{private},
            description      => $args{desc},
            full_description => $args{full_desc},
        },
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 201;

            if ( $res->{result}->{__all__} ) {
                $res->{reason} = $res->{result}->{__all__}->[0] if $res->{result}->{__all__}->[0];
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub create_automated_build ( $self, $repo_name, % ) {
    my %args = (
        repo_owner    => $self->username,
        private       => 0,
        active        => 1,
        provider      => undef,             # bitbucket, github
        vcs_repo_name => undef,             # source repository repo_owner/repo_name
        desc          => q[],
        build_tags    => [
            {   'name'                => '{sourceref}',    # docker build tag name
                'source_type'         => 'Tag',            # Branch, Tag
                'source_name'         => '/.*/',           # barnch / tag name in the source repository
                'dockerfile_location' => '/',
            },
        ],
        cb => undef,
        splice @_,
        2
    );

    return $self->_request(
        'post',
        "/repositories/$args{repo_owner}/$repo_name/autobuild/",
        1,
        {   name                => $repo_name,
            namespace           => $args{repo_owner},
            is_private          => $args{private},
            active              => $args{active} ? $TRUE : $FALSE,
            dockerhub_repo_name => "$args{repo_owner}/$repo_name",
            provider            => $args{provider},
            vcs_repo_name       => $args{vcs_repo_name},
            description         => $args{desc},
            build_tags          => $args{build_tags},
        },
        $args{cb}
    );
}

sub delete_repo ( $self, $repo_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request(
        'delete',
        "/repositories/$args{repo_owner}/$repo_name/",
        1, undef,
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 202;

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# special repo owner "library" can be used to get official repositories
sub get_repo ( $self, $repo_name = undef, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    $repo_name //= q[];

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/", 1, undef, $args{cb} );
}

sub get_repos ( $self, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 1
    );

    return $self->_request( 'get', "/users/$args{repo_owner}/repositories/", 1, undef, $args{cb} );
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

# BUILD
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
        repo_owner            => $self->username,
        cb                    => undef,
        'name'                => '{sourceref}',     # docker build tag name
        'source_type'         => 'Tag',             # Branch, Tag
        'source_name'         => '/.*/',            # barnch / tag name in the source repository
        'dockerfile_location' => '/',
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
        repo_owner            => $self->username,
        cb                    => undef,
        'name'                => '{sourceref}',     # docker build tag name
        'source_type'         => 'Tag',             # Branch, Tag
        'source_name'         => '/.*/',            # barnch / tag name in the source repository
        'dockerfile_location' => '/',
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

# WEBHOOK
sub create_webhook ( $self, $repo_name, $webhook_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'post', "/repositories/$args{repo_owner}/$repo_name/webhooks/", 1, { name => $webhook_name }, $args{cb} );
}

sub create_webhook_hook ( $self, $repo_name, $webhook_id, $url % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 4
    );

    return $self->_request( 'post', "/repositories/$args{repo_owner}/$repo_name/webhooks/$webhook_id/hooks/", 1, { hook_url => $url }, $args{cb} );
}

sub get_webhooks ( $self, $repo_name, % ) {
    my %args = (
        page       => 1,
        page_size  => 100,
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/webhooks/?page_size=$args{page_size}&page=$args{page}", 1, undef, $args{cb} );
}

sub delete_webhook ( $self, $repo_name, $webhook_id, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'delete', "/repositories/$args{repo_owner}/$repo_name/webhooks/$webhook_id/", 1, undef, $args{cb} );
}

# PRIVATE METHODS
sub _request ( $self, $type, $path, $auth, $data, $cb ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $request = sub {
        P->http->$type(
            $URL . $path,
            headers => {
                CONTENT_TYPE => 'application/json',
                $auth ? ( AUTHORIZATION => 'JWT ' . $self->{login_token} ) : (),
            },
            body => $data ? P->data->to_json($data) : undef,
            on_finish => sub ($res) {
                my $api_res = Pcore::API::Response->new( { status => $res->status, reason => $res->reason } );

                $api_res->{result} = P->data->from_json( $res->body ) if $res->body && $res->body->$*;

                $cb->($api_res) if $cb;

                $blocking_cv->send($api_res) if $blocking_cv;

                return;
            }
        );
    };

    if ( !$auth ) {
        $request->();
    }
    elsif ( $self->{login_token} ) {
        $request->();
    }
    else {
        $self->login(
            cb => sub ($res) {
                if ( $res->is_success ) {
                    $request->();
                }
                else {
                    $cb->($res) if $cb;

                    $blocking_cv->send($res) if $blocking_cv;
                }

                return;
            }
        );
    }

    return $blocking_cv ? $blocking_cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 54, 74, 214, 225,    │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## │      │ 282, 307, 339, 361,  │                                                                                                                │
## │      │ 372, 382, 404, 415   │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 89, 90               │ ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 131, 265, 289        │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 17, 44, 55, 65, 75,  │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## │      │ 86, 120, 158, 180,   │                                                                                                                │
## │      │ 192, 203, 215, 226,  │                                                                                                                │
## │      │ 236, 248, 259, 283,  │                                                                                                                │
## │      │ 308, 319, 329, 340,  │                                                                                                                │
## │      │ 352, 362, 373, 383,  │                                                                                                                │
## │      │ 393, 405             │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::DockerHub

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
