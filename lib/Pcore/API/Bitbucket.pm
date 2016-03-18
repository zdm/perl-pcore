package Pcore::API::Bitbucket;

use Pcore -class;
use Pcore::API::Response;
use Pcore::API::Bitbucket::Issue;

has repo_owner   => ( is => 'ro', isa => Str, required => 1 );
has repo_name    => ( is => 'ro', isa => Str, required => 1 );
has api_username => ( is => 'ro', isa => Str, required => 1 );
has api_password => ( is => 'ro', isa => Str, required => 1 );

has auth => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_auth ($self) {
    return 'Basic ' . P->data->to_b64( $self->api_username . q[:] . $self->api_password, q[] );
}

sub issues ( $self, @ ) {
    my $cb = $_[-1];

    # https://confluence.atlassian.com/bitbucket/issues-resource-296095191.html#issuesResource-GETalistofissuesinarepository%27stracker
    my %args = (
        limit     => 50,
        id        => undef,
        sort      => 'priority',    # priority, kind, version, component, milestone
        status    => undef,
        milestone => undef,
        splice @_, 1, -1,
    );

    my $id = delete $args{id};

    my $url = do {
        if ($id) {
            "https://bitbucket.org/api/1.0/repositories/@{[$self->repo_owner]}/@{[$self->repo_name]}/issues/$id";
        }
        else {
            "https://bitbucket.org/api/1.0/repositories/@{[$self->repo_owner]}/@{[$self->repo_name]}/issues/?" . P->data->to_uri( \%args );
        }
    };

    P->http->get(    #
        $url,
        headers   => { AUTHORIZATION => $self->auth },
        on_finish => sub ($res) {
            my $json = P->data->from_json( $res->body );

            if ($id) {
                my $issue;

                if ($json) {
                    $issue = Pcore::API::Bitbucket::Issue->new( { api => $self } );

                    $issue->@{ keys $json->%* } = values $json->%*;
                }

                $cb->($issue);
            }
            else {
                my $issues;

                if ( $json->{issues}->@* ) {
                    for ( $json->{issues}->@* ) {
                        my $issue = Pcore::API::Bitbucket::Issue->new( { api => $self } );

                        $issue->@{ keys $_->%* } = values $_->%*;

                        push $issues->@*, $issue;
                    }
                }

                $cb->($issues);
            }

            return;
        },
    );

    return;
}

sub create_version ( $self, $ver, $cb ) {
    my $url = "https://api.bitbucket.org/1.0/repositories/@{[$self->repo_owner]}/@{[$self->repo_name]}/issues/versions";

    $ver = version->parse($ver)->normal;

    P->http->post(    #
        $url,
        headers => {
            AUTHORIZATION => $self->auth,
            CONTENT_TYPE  => 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body      => P->data->to_uri( { name => $ver } ),
        on_finish => sub ($res) {
            my $id;

            $id = P->data->from_json( $res->body )->{id} if $res->status == 200;

            $cb->($id);

            return;
        },
    );

    return;
}

sub create_milestone ( $self, $milestone, $cb ) {
    my $url = "https://api.bitbucket.org/1.0/repositories/@{[$self->repo_owner]}/@{[$self->repo_name]}/issues/milestones";

    P->http->post(    #
        $url,
        headers => {
            AUTHORIZATION => $self->auth,
            CONTENT_TYPE  => 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body      => P->data->to_uri( { name => $milestone } ),
        on_finish => sub ($res) {
            my $id;

            $id = P->data->from_json( $res->body )->{id} if $res->status == 200;

            $cb->($id);

            return;
        },
    );

    return;
}

sub set_issue_status ( $self, $id, $status, $cb ) {
    my $issue = Pcore::API::Bitbucket::Issue->new( { api => $self } );

    $issue->{local_id} = $id;

    $issue->set_status( $status, $cb );

    return;
}

sub create_repository ( $self, @ ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my %args = (
        cb          => undef,
        scm         => 'hg',             # hg, git
        is_private  => 0,
        description => undef,
        fork_police => 'allow_forks',    # allow_forks, no_public_forks, no_forks
        language    => 'perl',
        has_issues  => 1,
        has_wiki    => 1,
        splice @_, 1
    );

    my $cb = delete $args{cb};

    my $url = "https://api.bitbucket.org/2.0/repositories/@{[$self->repo_owner]}/@{[$self->repo_name]}";

    P->http->post(                       #
        $url,
        headers => {
            AUTHORIZATION => $self->auth,
            CONTENT_TYPE  => 'application/json',
        },
        body      => P->data->to_json( \%args ),
        on_finish => sub ($res) {
            my $api_res;

            if ( $res->status != 200 ) {
                $api_res = Pcore::API::Response->new( { status => $res->status, reason => $res->reason } );
            }
            else {
                my $json = P->data->from_json( $res->body );

                if ( $json->{error} ) {
                    $api_res = Pcore::API::Response->new( { status => 999, reason => $json->{error}->{message} } );
                }
                else {
                    say dump $json;

                    $api_res = Pcore::API::Response->new( { status => 200 } );
                }
            }

            $cb->($api_res) if $cb;

            $blocking_cv->send($api_res) if $blocking_cv;

            return;
        },
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 54, 66               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 145                  │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Bitbucket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
