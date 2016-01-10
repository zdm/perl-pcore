package Pcore::API::Bitbucket;

use Pcore -class;

has account_name => ( is => 'ro', isa => Str, required => 1 );
has repo_slug    => ( is => 'ro', isa => Str, required => 1 );

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

has auth => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_auth ($self) {
    return 'Basic ' . P->data->to_b64( $self->username . q[:] . $self->password, q[] );
}

sub issues ( $self, @ ) {
    state $init = !!require Pcore::API::Bitbucket::Issue;

    my $cb = $_[-1];

    # https://confluence.atlassian.com/bitbucket/issues-resource-296095191.html#issuesResource-GETalistofissuesinarepository%27stracker
    my %args = (
        id      => undef,
        sort    => 'priority',    # priority, kind, version, component, milestone
        status  => undef,
        version => undef,
        splice @_, 1, -1,
    );

    my $id = delete $args{id};

    my $url = do {
        if ($id) {
            "https://bitbucket.org/api/1.0/repositories/@{[$self->account_name]}/@{[$self->repo_slug]}/issues/$id";
        }
        else {
            "https://bitbucket.org/api/1.0/repositories/@{[$self->account_name]}/@{[$self->repo_slug]}/issues/?" . P->data->to_uri( \%args );
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
    my $url = "https://api.bitbucket.org/1.0/repositories/@{[$self->account_name]}/@{[$self->repo_slug]}/issues/versions";

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

sub create_milestone ( $self, $ver, $cb ) {
    my $url = "https://api.bitbucket.org/1.0/repositories/@{[$self->account_name]}/@{[$self->repo_slug]}/issues/milestones";

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

sub set_issue_status ( $self, $id, $status, $cb ) {
    state $init = !!require Pcore::API::Bitbucket::Issue;

    my $issue = Pcore::API::Bitbucket::Issue->new( { api => $self } );

    $issue->{local_id} = $id;

    $issue->set_status( $status, $cb );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 54, 66               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
