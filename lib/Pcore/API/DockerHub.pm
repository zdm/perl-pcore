package Pcore::API::DockerHub;

use Pcore -const, -class;
use Pcore::API::Response;

# https://github.com/RyanTheAllmighty/Docker-Hub-API.git

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

has login_token => ( is => 'ro', isa => Str, init_arg => undef );

const our $API_VERSION => 2;
const our $URL         => "https://hub.docker.com/v$API_VERSION";

sub login ( $self, $cb = undef ) {
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

            $cb->($res) if $cb;

            return;
        }
    );
}

sub user ( $self, $username = undef, $cb = undef ) {
    $username //= $self->username;

    return $self->_request( 'get', '/users/' . lc $username . q[/], undef, undef, $cb );
}

sub create_repo ( $self, $repo_name, @ ) {
    my $cb = ref $_[-1] eq 'CODE' ? pop : undef;

    my %args = (
        repo_owner => $self->username,
        private    => 0,
        desc       => '',
        full_desc  => '',
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

            $cb->($res) if $cb;

            return;
        }
    );
}

sub delete_repo ( $self, $repo_name, @ ) {
    my $cb = ref $_[-1] eq 'CODE' ? pop : undef;

    my %args = (
        repo_owner => $self->username,
        splice @_, 2
    );

    return $self->_request(
        'delete',
        "/repositories/$args{repo_owner}/$repo_name/",
        1, undef,
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 202;

            $cb->($res) if $cb;

            return;
        }
    );
}

# special repo owner "library" can be used to get official repositories
sub repo ( $self, $repo_name = undef, $repo_owner = undef, @ ) {
    my $cb = ref $_[-1] eq 'CODE' ? pop : undef;

    $repo_name //= q[];

    $repo_owner //= $self->username;

    return $self->_request( 'get', '/repositories/' . lc $repo_owner . "/$repo_name/", 1, undef, $cb );
}

sub repos ( $self, $username = undef, $cb = undef ) {
    $username //= $self->username;

    return $self->_request( 'get', '/users/' . lc $username . '/repositories/', 1, undef, $cb );
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
            sub ($res) {
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
## │    3 │ 102, 118             │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 50, 51               │ ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 47, 82               │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
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
