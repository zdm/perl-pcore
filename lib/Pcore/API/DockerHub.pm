package Pcore::API::DockerHub1;

use Pcore -const, -class, -result, -export => [ CONST => [qw[$DOCKERHUB_PROVIDER_BITBUCKET $DOCKERHUB_PROVIDER_GITHUB $DOCKERHUB_SOURCE_TYPE_TAG $DOCKERHUB_SOURCE_TYPE_BRANCH]] ];
use Pcore::Util::Scalar qw[is_plain_coderef];

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

has _login_token => ( is => 'ro', isa => Str, init_arg => undef );
has _reg_queue => ( is => 'ro', isa => HashRef [ArrayRef], init_arg => undef );

const our $BASE_URL => 'https://hub.docker.com/v2';

const our $DOCKERHUB_PROVIDER_BITBUCKET => 1;
const our $DOCKERHUB_PROVIDER_GITHUB    => 2;

const our $DOCKERHUB_PROVIDER_NAME => {
    $DOCKERHUB_PROVIDER_BITBUCKET => 'bitbucket',
    $DOCKERHUB_PROVIDER_GITHUB    => 'github',
};

const our $DOCKERHUB_SOURCE_TYPE_TAG    => 1;
const our $DOCKERHUB_SOURCE_TYPE_BRANCH => 2;

const our $DOCKERHUB_SOURCE_TYPE_NAME => {
    $DOCKERHUB_SOURCE_TYPE_TAG    => 'Tag',
    $DOCKERHUB_SOURCE_TYPE_BRANCH => 'Branch',
};

const our $DEF_PAGE_SIZE => 250;

const our $BUILD_STATUS_TEXT => {
    -4 => 'cancelled',
    -1 => 'error',
    0  => 'queued',
    3  => 'building',
    10 => 'success',
};

sub BUILDARGS ( $self, $args = undef ) {
    $args->{username} ||= $ENV->user_cfg->{DOCKERHUB}->{username};

    $args->{password} ||= $ENV->user_cfg->{DOCKERHUB}->{password};

    return $args;
}

sub _login ( $self, $cb ) {
    state $endpoint = '/users/login/';

    if ( $self->{_login_token} ) {
        $cb->( $self->{_login_token} );

        return;
    }

    push $self->{_req_queue}->{$endpoint}->@*, $cb;

    return if $self->{_req_queue}->{$endpoint}->@* > 1;

    return $self->_req(
        'post',
        $endpoint,
        undef,
        {   username => $self->{username},
            password => $self->{password},
        },
        sub ($res) {
            if ( !$res ) {
                $res->{reason} = $res->{data}->{detail} if $res->{data}->{detail};
            }
            elsif ( $res->{data}->{token} ) {
                $self->{_login_token} = delete $res->{data}->{token};
            }

            $cb->($res);

            return;
        }
    );
}

sub _req ( $self, $method, $endpoint, $require_auth, $data, $cb ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $request = sub {
        P->http->$method(
            $BASE_URL . $endpoint,
            headers => {
                CONTENT_TYPE => 'application/json',
                $require_auth ? ( AUTHORIZATION => 'JWT ' . $self->{_login_token} ) : (),
            },
            body => $data ? P->data->to_json($data) : undef,
            on_finish => sub ($res) {
                my $api_res = result [ $res->status, $res->reason ], $res->body && $res->body->$* ? P->data->from_json( $res->body ) : ();

                $cb->($api_res) if $cb;

                $blocking_cv->send($api_res) if $blocking_cv;

                return;
            }
        );
    };

    if ( !$require_auth ) {
        $request->();
    }
    elsif ( $self->{_login_token} ) {
        $request->();
    }
    else {
        $self->_login(
            sub ($res) {

                # login ok
                if ($res) {
                    $request->();
                }

                # login failure
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

# USER / NAMESPACE
sub get_user ( $self, $username, $cb = undef ) {
    return $self->_req( 'get', "/users/$username/", undef, undef, $cb );
}

sub get_user_registry_settings ( $self, $username, $cb = undef ) {
    return $self->_req( 'get', "/users/$username/registry-settings/", 1, undef, $cb );
}

# CREATE REPO / AUTOMATED BUILD
sub create_repo ( $self, $repo_id, $desc, @args ) {
    my $cb = is_plain_coderef $args[-1] ? pop @args : undef;

    my %args = (
        private   => 0,
        full_desc => q[],
        @args
    );

    my ( $namespace, $name ) = split m[/]sm, $repo_id;

    return $self->_req(
        'post',
        '/repositories/',
        1,
        {   namespace        => $namespace,
            name             => $name,
            is_private       => $args{private},
            description      => $desc,
            full_description => $args{full_desc},
        },
        $cb
    );
}

sub create_autobuild ( $self, $repo_id, $scm_provider, $scm_repo_name, $desc, @args ) {
    my $cb = is_plain_coderef $args[-1] ? pop @args : undef;

    my %args = (
        desc       => undef,
        private    => 0,
        active     => 1,
        build_tags => undef,
        @args,
    );

    my ( $namespace, $name ) = split m[/]sm, $repo_id;

    my $build_tags;

    # prepare build tags
    if ( !$args{build_tags} ) {
        $build_tags = [
            {   name                => '{sourceref}',                                                # docker build tag name
                source_type         => $DOCKERHUB_SOURCE_TYPE_NAME->{$DOCKERHUB_SOURCE_TYPE_TAG},    # Branch, Tag
                source_name         => '/.*/',                                                       # barnch / tag name in the source repository
                dockerfile_location => q[/],
            },
        ];
    }
    else {
        for ( $args{build_tags}->@* ) {
            my %build_tags = $_->%*;

            $build_tags{source_type} = $DOCKERHUB_SOURCE_TYPE_NAME->{ $build_tags{source_type} };

            push $build_tags->@*, \%build_tags;
        }
    }

    return $self->request(
        'post',
        "/repositories/$repo_id/autobuild/",
        1,
        {   namespace           => $namespace,
            name                => $name,
            description         => $desc,
            is_private          => $args{private} ? \1 : \0,
            active              => $args{active} ? \1 : \0,
            dockerhub_repo_name => $repo_id,
            provider            => $DOCKERHUB_PROVIDER_NAME->{$scm_provider},
            vcs_repo_name       => $scm_repo_name,
            description         => $desc,
            build_tags          => $build_tags,
        },
        $cb
    );
}

# REPO
sub get_all_repos ( $self, $namespace, $cb = undef ) {
    return $self->_req(
        'get',
        "/users/$namespace/repositories/",
        1, undef,
        sub ($res) {
            if ($res) {
                my $data;

                for my $repo ( $res->{data}->@* ) {
                    $repo->{id} = "$repo->{namespace}/$repo->{name}";

                    $data->{ $repo->{id} } = $repo;
                }

                $res->{data} = $data;
            }

            $cb->($res) if $cb;

            return;
        }
    );
}

sub get_repo ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'get',
        "/repositories/$repo_id/",
        1, undef,
        sub($res) {
            if ($res) {
                $res->{data}->{id} = $repo_id;
            }

            $cb->($res) if $cb;

            return;
        }
    );
}

sub remove_repo ( $self, $repo_id, $cb = undef ) {
    return $self->_req( 'delete', "/repositories/$repo_id/", 1, undef, $cb );
}

sub set_desc ( $self, $repo_id, $desc, $cb = undef ) {
    return $self->_req( 'patch', "/repositories/$repo_id/", 1, { description => $desc }, $cb );
}

sub set_full_desc ( $self, $repo_id, $desc, $cb = undef ) {
    return $self->_req( 'patch', "/repositories/$repo_id/", 1, { full_description => $desc }, $cb );
}

# REPO TAGS
# TODO gel all pages
sub get_tags ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'get',
        "/repositories/$repo_id/tags/?page_size=$DEF_PAGE_SIZE&page=1",
        1, undef,
        sub ($res) {
            if ($res) {
                my $data;

                for my $tag ( $res->{data}->{results}->@* ) {
                    $data->{ $tag->{id} } = $tag;
                }

                $res->{data} = $data;
            }

            $cb->($res) if $cb;

            return;
        }
    );
}

sub delete_tag ( $self, $repo_id, $tag_name, $cb = undef ) {
    return $self->_req( 'delete', "/repositories/$repo_id/tags/$tag_name/", 1, undef, $cb );
}

# REPO WEBHOOKS
# TODO get all pages
sub get_webhooks ( $self, $repo_id, $cb = undef ) {
    return $self->_req( 'get', "/repositories/$repo_id/webhooks/?page_size=$DEF_PAGE_SIZE&page=1", 1, undef, $cb );
}

sub create_webhook ( $self, $repo_id, $webhook_name, $webhook_url, $cb = undef ) {
    return $self->_req(
        'post',
        "/repositories/$repo_id/webhook_pipeline/",
        1,
        {   name                  => $webhook_name,
            expect_final_callback => \0,
            webhooks              => [
                {   name     => $webhook_name,
                    hook_url => $webhook_url,
                }
            ],
        },
        $cb
    );
}

sub delete_webhook ( $self, $repo_id, $webhook_name, $cb = undef ) {
    return $self->_req( 'delete', "/repositories/$repo_id/webhook_pipeline/$webhook_name/", 1, undef, $cb );
}

# AUTOBUILD LINKS
sub get_autobuild_links ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'get',
        "/repositories/$repo_id/links/",
        1, undef,
        sub ($res) {
            if ($res) {
                my $data;

                for my $link ( $res->{data}->{results}->@* ) {
                    $data->{ $link->{id} } = $link;
                }

                $res->{data} = $data;
            }

            $cb->($res) if $cb;

            return;
        }
    );
}

sub create_autobuild_link ( $self, $repo_id, $target_repo_id, $cb = undef ) {
    return $self->_req( 'post', "/repositories/$repo_id/links/", 1, { to_repo => $target_repo_id }, $cb );
}

sub delete_autobuild_link ( $self, $repo_id, $link_id, $cb = undef ) {
    return $self->_req( 'delete', "/repositories/$repo_id/links/$link_id/", 1, undef, $cb );
}

# BUILD
# TODO get all pages
sub get_build_history ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'get',
        "/repositories/$repo_id/buildhistory/?page_size=$DEF_PAGE_SIZE&page=1",
        1, undef,
        sub ($res) {
            if ($res) {
                my $data;

                for my $build ( $res->{data}->{results}->@* ) {
                    $data->{ $build->{id} } = $build;

                    $build->{status_text} = $BUILD_STATUS_TEXT->{ $build->{status} };
                }

                $res->{data} = $data;
            }

            $cb->($res) if $cb;

            return;
        }
    );
}

sub trigger_autobuild ( $self, $repo_id, $source_name, $source_type, $cb = undef ) {
    return $self->_req(
        'post',
        "/repositories/$repo_id/autobuild/trigger-build/",
        1,
        {   source_name         => $source_name,
            source_type         => $DOCKERHUB_SOURCE_TYPE_NAME->{$source_type},
            dockerfile_location => '/',
        },
        $cb
    );
}

sub get_autobuild_details ( $self, $repo_id, $cb = undef ) {
    return $self->_req( 'get', "/repositories/$repo_id/autobuild/", 1, undef, $cb );
}

# AUTOBUILD TAGS
sub get_autobuild_tags ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'get',
        "/repositories/$repo_id/autobuild/tags/",
        1, undef,
        sub ($res) {
            if ($res) {
                my $data;

                for my $tag ( $res->{data}->{results}->@* ) {
                    $data->{ $tag->{id} } = $tag;
                }

                $res->{data} = $data;
            }

            $cb->($res) if $cb;

            return;
        }
    );
}

sub create_autobuild_tag ( $self, $repo_id, $source_name, $source_type, $cb = undef ) {
    my ( $namespace, $name ) = split m[/]sm, $repo_id;

    return $self->_req(
        'post',
        "/repositories/$repo_id/autobuid/tags/",
        1,
        {   name                => 1,
            dockerfile_location => '/',
            source_name         => $source_name,
            source_type         => $DOCKERHUB_SOURCE_TYPE_NAME->{$source_type},
            isNew               => \1,
            repoName            => $name,
            namespace           => $namespace,
        },
        $cb
    );
}

sub delete_autobuild_tag ( $self, $repo_id, $autobuild_tag_id, $cb = undef ) {
    return $self->_req( 'delete', "/repositories/$repo_id/autobuid/$autobuild_tag_id/", 1, undef, $cb );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 83, 171, 305, 315,   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 332, 360, 364, 395,  |                                                                                                                |
## |      | 436, 455             |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 149                  | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::DockerHub1

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
