package Pcore::API::Docker::Cloud;

use Pcore -const, -class, -res, -export;
use Pcore::Util::Scalar qw[is_plain_coderef];

our $EXPORT = { DOCKERHUB_SOURCE_TYPE => [qw[$DOCKERHUB_SOURCE_TYPE_TAG $DOCKERHUB_SOURCE_TYPE_BRANCH]] };

has username => ( required => 1 );
has password => ( required => 1 );

has _login_token => ( init_arg => undef );
has _reg_queue   => ( init_arg => undef );    # HashRef [ArrayRef]

const our $BASE_URL => 'https://hub.docker.com/v2';

const our $DOCKERHUB_SOURCE_TYPE_TAG    => 'tag';
const our $DOCKERHUB_SOURCE_TYPE_BRANCH => 'branch';

const our $DOCKERHUB_SOURCE_TYPE_NAME => {
    $DOCKERHUB_SOURCE_TYPE_TAG    => 'Tag',
    $DOCKERHUB_SOURCE_TYPE_BRANCH => 'Branch',
};

const our $DEF_PAGE_SIZE => 250;

const our $BUILD_STATUS_TEXT => {
    -4 => 'cancelled',
    -2 => 'error',
    -1 => 'error',
    0  => 'queued',
    1  => 'queued',
    2  => 'building',
    3  => 'building',
    10 => 'success',
    11 => 'queued',
};

sub BUILDARGS ( $self, $args = undef ) {
    $args->{username} ||= $ENV->user_cfg->{DOCKER}->{username};

    $args->{password} ||= $ENV->user_cfg->{DOCKER}->{password};

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
        'POST',
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

            while ( my $cb = shift $self->{_req_queue}->{$endpoint}->@* ) {
                $cb->($res);
            }

            return;
        }
    );
}

sub _req ( $self, $method, $endpoint, $require_auth, $data, $cb = undef ) {
    my $cv = P->cv;

    my $request = sub {
        P->http->request(
            method  => $method,
            url     => $BASE_URL . $endpoint,
            headers => [
                'Content-Type' => 'application/json',
                $require_auth ? ( Authorization => 'JWT ' . $self->{_login_token} ) : (),
            ],
            data => $data ? P->data->to_json($data) : undef,
            sub ($res) {
                my $api_res = res [ $res->{status}, $res->{reason} ], $res->{data} && $res->{data}->$* ? P->data->from_json( $res->{data} ) : ();

                $cv->( $cb ? $cb->($api_res) : $api_res );

                return;
            }
        );

        return;
    };

    if ( !$require_auth ) {
        $request->();
    }
    elsif ( $self->{_login_token} ) {
        $request->();
    }
    else {
        $self->_login( sub ($res) {

            # login ok
            if ($res) {
                $request->();
            }

            # login failure
            else {
                $cv->( $cb ? $cb->($res) : $res );
            }

            return;
        } );
    }

    return defined wantarray ? $cv->recv : ();
}

# USER / NAMESPACE
sub get_user ( $self, $username, $cb = undef ) {
    return $self->_req( 'GET', "/users/$username/", undef, undef, $cb );
}

sub get_user_registry_settings ( $self, $username, $cb = undef ) {
    return $self->_req( 'GET', "/users/$username/registry-settings/", 1, undef, $cb );
}

sub get_user_orgs ( $self, $cb = undef ) {
    return $self->_req(
        'GET',
        "/user/orgs/?page_size=$DEF_PAGE_SIZE&page=1",
        1, undef,
        sub ($res) {
            if ($res) {
                my $data;

                for my $org ( $res->{data}->{results}->@* ) {
                    $data->{ $org->{orgname} } = $org;
                }

                $res->{data} = $data;
            }

            return $cb ? $cb->($res) : $res;
        }
    );
}

# CREATE REPO / AUTOMATED BUILD
sub create_repo ( $self, $repo_id, $desc, @args ) {
    my $cb = is_plain_coderef $args[-1] ? pop @args : undef;

    my %args = (
        private   => 0,
        full_desc => $EMPTY,
        @args
    );

    my ( $namespace, $name ) = split m[/]sm, $repo_id;

    return $self->_req(
        'POST',
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

sub create_autobuild ( $self, $repo_id, $scm_provider, $scm_repo_id, $desc, @args ) {
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
                dockerfile_location => '/',
            },
        ];
    }
    else {
        for ( $args{build_tags}->@* ) {
            my %build_tags = $_->%*;

            $build_tags{source_type} = $DOCKERHUB_SOURCE_TYPE_NAME->{ lc $build_tags{source_type} };

            push $build_tags->@*, \%build_tags;
        }
    }

    return $self->_req(
        'POST',
        "/repositories/$repo_id/autobuild/",
        1,
        {   namespace           => $namespace,
            name                => $name,
            description         => $desc,
            is_private          => $args{private} ? \1 : \0,
            active              => $args{active} ? \1 : \0,
            dockerhub_repo_name => $repo_id,
            provider            => $scm_provider,
            vcs_repo_name       => $scm_repo_id,
            description         => $desc,
            build_tags          => $build_tags,
        },
        $cb
    );
}

# REPO
sub get_all_repos ( $self, $namespace, $cb = undef ) {
    return $self->_req(
        'GET',
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

            return $cb ? $cb->($res) : $res;
        }
    );
}

sub get_repo ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'GET',
        "/repositories/$repo_id/",
        1, undef,
        sub($res) {
            if ($res) {
                $res->{data}->{id} = $repo_id;
            }

            return $cb ? $cb->($res) : $res;
        }
    );
}

sub remove_repo ( $self, $repo_id, $cb = undef ) {
    return $self->_req( 'DELETE', "/repositories/$repo_id/", 1, undef, $cb );
}

sub set_desc ( $self, $repo_id, $desc, $cb = undef ) {
    return $self->_req( 'PATCH', "/repositories/$repo_id/", 1, { description => $desc }, $cb );
}

sub set_full_desc ( $self, $repo_id, $desc, $cb = undef ) {
    return $self->_req( 'PATCH', "/repositories/$repo_id/", 1, { full_description => $desc }, $cb );
}

# REPO TAGS
# TODO gel all pages
sub get_tags ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'GET',
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

            return $cb ? $cb->($res) : $res;
        }
    );
}

sub delete_tag ( $self, $repo_id, $tag_name, $cb = undef ) {
    return $self->_req( 'DELETE', "/repositories/$repo_id/tags/$tag_name/", 1, undef, $cb );
}

# REPO WEBHOOKS
# TODO get all pages
sub get_webhooks ( $self, $repo_id, $cb = undef ) {
    return $self->_req( 'GET', "/repositories/$repo_id/webhooks/?page_size=$DEF_PAGE_SIZE&page=1", 1, undef, $cb );
}

sub create_webhook ( $self, $repo_id, $webhook_name, $webhook_url, $cb = undef ) {
    return $self->_req(
        'POST',
        "/repositories/$repo_id/webhook_pipeline/",
        1,
        {   name                  => $webhook_name,
            expect_final_callback => \0,
            webhooks              => [ {
                name     => $webhook_name,
                hook_url => $webhook_url,
            } ],
        },
        $cb
    );
}

sub delete_webhook ( $self, $repo_id, $webhook_name, $cb = undef ) {
    return $self->_req( 'DELETE', "/repositories/$repo_id/webhook_pipeline/$webhook_name/", 1, undef, $cb );
}

# AUTOBUILD LINKS
sub get_autobuild_links ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'GET',
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

            return $cb ? $cb->($res) : $res;
        }
    );
}

sub create_autobuild_link ( $self, $repo_id, $target_repo_id, $cb = undef ) {
    return $self->_req( 'POST', "/repositories/$repo_id/links/", 1, { to_repo => $target_repo_id }, $cb );
}

sub delete_autobuild_link ( $self, $repo_id, $link_id, $cb = undef ) {
    return $self->_req( 'DELETE', "/repositories/$repo_id/links/$link_id/", 1, undef, $cb );
}

# BUILD
# TODO get all pages
sub get_build_history ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'GET',
        "/repositories/$repo_id/buildhistory/?page_size=$DEF_PAGE_SIZE&page=1",
        1, undef,
        sub ($res) {
            if ($res) {
                my $data;

                for my $build ( $res->{data}->{results}->@* ) {
                    $data->{ $build->{id} } = $build;

                    $build->{status_text} = exists $BUILD_STATUS_TEXT->{ $build->{status} } ? $BUILD_STATUS_TEXT->{ $build->{status} } : $build->{status};
                }

                $res->{data} = $data;
            }

            return $cb ? $cb->($res) : $res;
        }
    );
}

sub get_autobuild_settings ( $self, $repo_id, $cb = undef ) {
    return $self->_req( 'GET', "/repositories/$repo_id/autobuild/", 1, undef, $cb );
}

sub unlink_tag ( $self, $repo_id, $tag_name, $cb = undef ) {
    my ( $delete_autobuild_tag_status, $delete_tag_status );

    my $cv = P->cv->begin( sub ($cv) {
        my $res = res [ 200, "autobuild: $delete_autobuild_tag_status->{reason}, tag: $delete_tag_status->{reason}" ];

        $cv->( $cb ? $cb->($res) : $res );

        return;
    } );

    $cv->begin;
    $self->delete_autobuild_tag_by_name(
        $repo_id,
        $tag_name,
        sub ($res) {
            $delete_autobuild_tag_status = $res;

            $cv->end;

            return;
        }
    );

    $cv->begin;
    $self->delete_tag(
        $repo_id,
        $tag_name,
        sub ($res) {
            $delete_tag_status = $res;

            $cv->end;

            return;
        }
    );

    $cv->end;

    return defined wantarray ? $cv->recv : ();
}

# AUTOBUILD TAGS
sub get_autobuild_tags ( $self, $repo_id, $cb = undef ) {
    return $self->_req(
        'GET',
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

            return $cb ? $cb->($res) : $res;
        }
    );
}

sub create_autobuild_tag ( $self, $repo_id, $tag_name, $source_name, $source_type, $dockerfile_location, $cb = undef ) {
    my ( $namespace, $name ) = split m[/]sm, $repo_id;

    return $self->_req(
        'POST',
        "/repositories/$repo_id/autobuild/tags/",
        1,
        {   name                => $tag_name,
            dockerfile_location => $dockerfile_location // '/',
            source_name         => $source_name,
            source_type         => $DOCKERHUB_SOURCE_TYPE_NAME->{ lc $source_type },
            isNew               => \1,
            repoName            => $name,
            namespace           => $namespace,
        },
        $cb
    );
}

sub delete_autobuild_tag_by_id ( $self, $repo_id, $autobuild_tag_id, $cb = undef ) {
    return $self->_req( 'DELETE', "/repositories/$repo_id/autobuild/tags/$autobuild_tag_id/", 1, undef, $cb );
}

sub delete_autobuild_tag_by_name ( $self, $repo_id, $autobuild_tag_name, $cb = undef ) {
    my $cv = P->cv;

    my $on_finish = sub ($res) { $cv->( $cb ? $cb->($res) : $res ) };

    # get autobuild tags
    $self->get_autobuild_tags(
        $repo_id,
        sub ($res) {
            if ( !$res ) {
                $on_finish->($res);
            }
            else {
                my $found_autobuild_tag;

                for my $autobuild_tag ( values $res->{data}->%* ) {
                    if ( $autobuild_tag->{name} eq $autobuild_tag_name ) {
                        $found_autobuild_tag = $autobuild_tag;

                        last;
                    }
                }

                if ( !$found_autobuild_tag ) {
                    $on_finish->( res [ 404, 'Autobuild tag was not found' ] );
                }
                else {
                    $self->delete_autobuild_tag_by_id( $repo_id, $found_autobuild_tag->{id}, $on_finish );
                }
            }

            return;
        }
    );

    return defined wantarray ? $cv->recv : ();
}

sub trigger_autobuild ( $self, $repo_id, $source_name, $source_type, $cb = undef ) {
    return $self->_req(
        'POST',
        "/repositories/$repo_id/autobuild/trigger-build/",
        1,
        {   source_name         => $source_name,
            source_type         => $DOCKERHUB_SOURCE_TYPE_NAME->{ lc $source_type },
            dockerfile_location => '/',
        },
        $cb
    );
}

sub trigger_autobuild_by_tag_name ( $self, $repo_id, $autobuild_tag_name, $cb = undef ) {
    my $cv = P->cv;

    my $on_finish = sub ($res) { $cv->( $cb ? $cb->($res) : $res ) };

    # get autobuild tags
    $self->get_autobuild_tags(
        $repo_id,
        sub ($res) {
            if ( !$res ) {
                $on_finish->($res);
            }
            else {
                my $found_autobuild_tag;

                for my $autobuild_tag ( values $res->{data}->%* ) {
                    if ( $autobuild_tag->{name} eq $autobuild_tag_name ) {
                        $found_autobuild_tag = $autobuild_tag;

                        last;
                    }
                }

                if ( !$found_autobuild_tag ) {
                    $on_finish->( res [ 404, 'Autobuild tag was not found' ] );
                }
                else {
                    $self->trigger_autobuild( $repo_id, $found_autobuild_tag->{source_name}, $found_autobuild_tag->{source_type}, $on_finish );
                }
            }

            return;
        }
    );

    return defined wantarray ? $cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 83, 189, 317, 327,   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 343, 369, 373, 406,  |                                                                                                                |
## |      | 470, 489, 493, 531,  |                                                                                                                |
## |      | 544                  |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 167                  | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Docker::Cloud

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
