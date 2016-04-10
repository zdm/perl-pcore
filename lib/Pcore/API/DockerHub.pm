package Pcore::API::DockerHub;

use Pcore -const, -class, -export => { CONST => [qw[$DOCKERHUB_PROVIDER_BITBUCKET $DOCKERHUB_PROVIDER_GITHUB]] };
use Pcore::API::Response;
use Pcore::API::DockerHub::Repository;

# https://github.com/RyanTheAllmighty/Docker-Hub-API.git

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

has login_token => ( is => 'ro', isa => Str, init_arg => undef );

const our $API_VERSION => 2;
const our $URL         => "https://hub.docker.com/v$API_VERSION";

const our $DOCKERHUB_PROVIDER_BITBUCKET => 1;
const our $DOCKERHUB_PROVIDER_GITHUB    => 2;

const our $DOCKERHUB_PROVIDER_NAME => {
    $DOCKERHUB_PROVIDER_BITBUCKET => 'bitbucket',
    $DOCKERHUB_PROVIDER_GITHUB    => 'github',
};

sub login ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->request(
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
        splice @_, 1
    );

    return $self->request( 'get', "/users/$args{username}/", undef, undef, $args{cb} );
}

sub get_registry_settings ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->request( 'get', "/users/@{[$self->username]}/registry-settings/", 1, undef, $args{cb} );
}

# GET REPOS
sub get_all_repos ( $self, % ) {
    my %args = (
        namespace => $self->username,
        cb        => undef,
        splice @_, 1
    );

    return $self->request(
        'get',
        "/users/$args{namespace}/repositories/",
        1, undef,
        sub ($res) {
            if ( $res->is_success ) {
                my $result = {};

                for my $repo ( $res->{result}->@* ) {
                    $repo = bless $repo, 'Pcore::API::DockerHub::Repository';

                    $repo->{status} = $res->status;

                    $repo->{api} = $self;

                    $result->{ $repo->id } = $repo;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub get_repos ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        namespace => $self->username,
        cb        => undef,
        splice @_, 1
    );

    return $self->request(
        'get',
        "/repositories/$args{namespace}/?page_size=$args{page_size}&page=$args{page}",
        1, undef,
        sub($res) {
            if ( $res->is_success ) {
                $res->{count} = delete $res->{result}->{count};

                $res->{next} = delete $res->{result}->{next};

                $res->{previous} = delete $res->{result}->{previous};

                my $result = {};

                for my $repo ( $res->{result}->{results}->@* ) {
                    $repo = bless $repo, 'Pcore::API::DockerHub::Repository';

                    $repo->{status} = $res->status;

                    $repo->{api} = $self;

                    $result->{ $repo->id } = $repo;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub get_starred_repos ( $self, % ) {
    my %args = (
        page      => 1,
        page_size => 100,
        namespace => $self->username,
        cb        => undef,
        splice @_, 1
    );

    return $self->request(
        'get',
        "/users/$args{namespace}/repositories/starred/?page_size=$args{page_size}&page=$args{page}",
        1, undef,
        sub($res) {
            if ( $res->is_success ) {
                $res->{count} = delete $res->{result}->{count};

                $res->{next} = delete $res->{result}->{next};

                $res->{previous} = delete $res->{result}->{previous};

                my $result = {};

                for my $repo ( $res->{result}->{results}->@* ) {
                    $repo = bless $repo, 'Pcore::API::DockerHub::Repository';

                    $repo->{status} = $res->status;

                    $repo->{api} = $self;

                    $result->{ $repo->id } = $repo;
                }

                $res->{result} = $result;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub get_repo ( $self, $repo_name = undef, % ) {
    my %args = (
        repo_owner => $self->username,
        cb         => undef,
        splice @_, 2
    );

    $repo_name //= q[];

    return $self->request(
        'get',
        "/repositories/$args{repo_owner}/$repo_name/",
        1, undef,
        sub($res) {
            if ( $res->is_success ) {
                my $repo = bless $res->{result}, 'Pcore::API::DockerHub::Repository';

                $repo->{status} = $res->status;

                $repo->{reason} = $res->reason;

                $repo->{api} = $self;

                $_[0] = $repo;

                $res = $repo;
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# CREATE REPO / AUTOMATED BUILD
sub create_repo ( $self, $repo_name, % ) {
    my %args = (
        namespace => $self->username,
        private   => 0,
        desc      => '',
        full_desc => '',
        cb        => undef,
        splice @_, 2
    );

    return $self->request(
        'post',
        '/repositories/',
        1,
        {   name             => $repo_name,
            namespace        => $args{namespace},
            is_private       => $args{private},
            description      => $args{desc},
            full_description => $args{full_desc},
        },
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 201;

            if ( $res->is_success ) {
                my $repo = bless $res->{result}, 'Pcore::API::DockerHub::Repository';

                $repo->{status} = $res->status;

                $repo->{reason} = $res->reason;

                $repo->{api} = $self;

                $_[0] = $repo;

                $res = $repo;
            }
            else {
                if ( $res->{result}->{__all__} ) {
                    $res->{reason} = $res->{result}->{__all__}->[0] if $res->{result}->{__all__}->[0];
                }
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

sub create_automated_build ( $self, $repo_name, $provider, $vcs_repo_name, $desc, % ) {
    my %args = (
        namespace => $self->username,
        private   => 0,
        active    => 1,

        # provider      => undef,             # MANDATORY, bitbucket, github
        # vcs_repo_name => undef,             # MANDATORY, source repository repo_owner/repo_name
        # desc       => q[],    # MANDATORY
        build_tags => [
            {   name                => '{sourceref}',    # docker build tag name
                source_type         => 'Tag',            # Branch, Tag
                source_name         => '/.*/',           # barnch / tag name in the source repository
                dockerfile_location => '/',
            },
        ],
        cb => undef,
        splice( @_, 5 ),
    );

    return $self->request(
        'post',
        "/repositories/$args{namespace}/$repo_name/autobuild/",
        1,
        {   name                => $repo_name,
            namespace           => $args{namespace},
            is_private          => $args{private},
            active              => $args{active} ? $TRUE : $FALSE,
            dockerhub_repo_name => "$args{namespace}/$repo_name",
            provider            => $DOCKERHUB_PROVIDER_NAME->{$provider},
            vcs_repo_name       => $vcs_repo_name,
            description         => $desc,
            build_tags          => $args{build_tags},
        },
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 201;

            if ( $res->is_success ) {
                my $repo = bless $res->{result}, 'Pcore::API::DockerHub::Repository';

                $repo->{status} = $res->status;

                $repo->{reason} = $res->reason;

                $repo->{api} = $self;

                $_[0] = $repo;

                $res = $repo;
            }
            else {
                if ( $res->{result}->{__all__} ) {
                    $res->{reason} = $res->{result}->{__all__}->[0] if $res->{result}->{__all__}->[0];
                }
            }

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

# PRIVATE METHODS
sub request ( $self, $type, $path, $auth, $data, $cb ) {
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
## │    3 │ 278, 342             │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 233, 234             │ ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 291                  │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 26, 53, 63, 73, 108, │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## │      │ 151, 194, 230        │                                                                                                                │
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
