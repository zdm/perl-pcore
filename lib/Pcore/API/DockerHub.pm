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

sub delete_build_tag ( $self, $repo_name, $build_tag_id, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'delete', "/repositories/$args{repo_owner}/$repo_name/autobuild/tags/$build_tag_id/", 1, undef, $args{cb} );
}

sub get_build_links ( $self, $repo_name, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    return $self->_request( 'get', "/repositories/$args{repo_owner}/$repo_name/links/", 1, undef, $args{cb} );
}

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

sub delete_build_link ( $self, $repo_name, $build_link_id, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 3
    );

    return $self->_request( 'delete', "/repositories/$args{repo_owner}/$repo_name/links/$build_link_id/", 1, undef, $args{cb} );
}

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
## │    3 │ 169, 201, 241, 251   │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 57, 58               │ ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 99                   │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 17, 44, 54, 88, 126, │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## │      │ 148, 160, 170, 180,  │                                                                                                                │
## │      │ 192, 202, 212, 222,  │                                                                                                                │
## │      │ 232, 242             │                                                                                                                │
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
