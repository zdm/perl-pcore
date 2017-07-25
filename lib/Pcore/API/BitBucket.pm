package Pcore::API::BitBucket;

use Pcore -class, -result;
use Pcore::Util::Scalar qw[is_plain_coderef];
use Pcore::API::Bitbucket::Issue;
use Pcore::API::SCM::Const qw[:ALL];

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

has _auth => ( is => 'lazy', isa => Str, init_arg => undef );

sub BUILDARGS ( $self, $args = undef ) {
    $args->{username} ||= $ENV->user_cfg->{BITBUCKET}->{username} if $ENV->user_cfg->{BITBUCKET}->{username};

    $args->{password} ||= $ENV->user_cfg->{BITBUCKET}->{password} if $ENV->user_cfg->{BITBUCKET}->{password};

    return $args;
}

sub _build__auth ($self) {
    return 'Basic ' . P->data->to_b64( "$self->{username}:$self->{password}", q[] );
}

# https://developer.atlassian.com/bitbucket/api/2/reference/resource/repositories/%7Busername%7D/%7Brepo_slug%7D#post
sub create_repo ( $self, $repo_id, @args ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $cb = is_plain_coderef $args[-1] ? pop @args : undef;

    my $args = {
        scm         => $SCM_TYPE_HG,
        is_private  => 0,
        description => undef,
        fork_police => 'allow_forks',    # allow_forks, no_public_forks, no_forks
        language    => 'perl',
        has_issues  => 1,
        has_wiki    => 1,
        @args
    };

    P->http->post(
        "https://api.bitbucket.org/2.0/repositories/$repo_id",
        headers => {
            AUTHORIZATION => $self->_auth,
            CONTENT_TYPE  => 'application/json',
        },
        body      => P->data->to_json($args),
        on_finish => sub ($res) {
            my $done = sub ($res) {
                $cb->($res) if $cb;

                $blocking_cv->send($res) if $blocking_cv;

                return;
            };

            if ( !$res ) {
                my $data = eval { P->data->from_json( $res->body ) };

                $done->( result [ $res->status, $data->{error}->{message} || $res->reason ] );
            }
            else {
                my $data = eval { P->data->from_json( $res->body ) };

                if ($@) {
                    $done->( result [ 500, 'Error decoding response' ] );
                }
                else {
                    $done->( result 201, $data );
                }
            }

            return;
        },
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# https://developer.atlassian.com/bitbucket/api/2/reference/resource/repositories/%7Busername%7D/%7Brepo_slug%7D#delete
sub delete_repo ( $self, $repo_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    P->http->delete(
        "https://api.bitbucket.org/2.0/repositories/$repo_id",
        headers => {
            AUTHORIZATION => $self->_auth,
            CONTENT_TYPE  => 'application/json',
        },
        on_finish => sub ($res) {
            my $done = sub ($res) {
                $cb->($res) if $cb;

                $blocking_cv->send($res) if $blocking_cv;

                return;
            };

            if ( !$res ) {
                my $data = eval { P->data->from_json( $res->body ) };

                $done->( result [ $res->status, $data->{error}->{message} || $res->reason ] );
            }
            else {
                $done->( result [ $res->status, $res->reason ] );
            }

            return;
        },
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# VERSIONS
# https://developer.atlassian.com/bitbucket/api/2/reference/resource/repositories/%7Busername%7D/%7Brepo_slug%7D/versions
sub get_versions ( $self, $cb ) {
    my $versions;

    state $get = sub ( $url, $cb ) {
        P->http->get(
            $url,
            headers => {    #
                AUTHORIZATION => $self->auth,
            },
            on_finish => sub ($res) {
                if ( !$res ) {
                    $cb->( result [ $res->status, $res->reason ] );
                }
                else {
                    my $data = eval { P->data->from_json( $res->body->$* ) };

                    if ($@) {
                        $cb->( result [ 500, 'Error decoding content' ] );
                    }
                    else {
                        $cb->( result 200, $data );
                    }
                }

                return;
            }
        );

        return;
    };

    my $process = sub ($res) {
        if ( !$res ) {
            $cb->($res);
        }
        else {
            for my $ver ( $res->{data}->{values}->@* ) {
                $versions->{ $ver->{name} } = $ver->{links}->{self}->{href};
            }

            if ( $res->{data}->{next} ) {
                $get->( $res->{data}->{next}, __SUB__ );
            }
            else {
                $cb->( result 200, $versions );
            }
        }

        return;
    };

    $get->( "https://api.bitbucket.org/2.0/repositories/@{[$self->id]}/versions", $process );

    return;
}

# https://confluence.atlassian.com/bitbucket/issues-resource-296095191.html#issuesResource-POSTanewversion
sub create_version ( $self, $ver, $cb ) {
    $ver = version->parse($ver)->normal;

    P->http->post(    #
        "https://api.bitbucket.org/1.0/repositories/@{[$self->id]}/issues/versions",
        headers => {
            AUTHORIZATION => $self->auth,
            CONTENT_TYPE  => 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body      => P->data->to_uri( { name => $ver } ),
        on_finish => sub ($res) {
            if ( !$res ) {
                if ( $res->body->$* =~ /already exists/sm ) {
                    $cb->( result 200, { name => $ver } );
                }
                else {
                    $cb->( result [ $res->status, $res->reason ] );
                }
            }
            else {
                my $data = eval { P->data->from_json( $res->body->$* ) };

                if ($@) {
                    $cb->( result [ 500, 'Error decoding content' ] );
                }
                else {
                    $cb->( result 201, $data );
                }
            }

            return;
        },
    );

    return;
}

# MILESTONES
# https://developer.atlassian.com/bitbucket/api/2/reference/resource/repositories/%7Busername%7D/%7Brepo_slug%7D/milestones
sub get_milestones ( $self, $cb ) {
    my $milestones;

    state $get = sub ( $url, $cb ) {
        P->http->get(
            $url,
            headers => {    #
                AUTHORIZATION => $self->auth,
            },
            on_finish => sub ($res) {
                if ( !$res ) {
                    $cb->( result [ $res->status, $res->reason ] );
                }
                else {
                    my $data = eval { P->data->from_json( $res->body->$* ) };

                    if ($@) {
                        $cb->( result [ 500, 'Error decoding content' ] );
                    }
                    else {
                        $cb->( result 200, $data );
                    }
                }

                return;
            }
        );

        return;
    };

    my $process = sub ($res) {
        if ( !$res ) {
            $cb->($res);
        }
        else {
            for my $ver ( $res->{data}->{values}->@* ) {
                $milestones->{ $ver->{name} } = $ver->{links}->{self}->{href};
            }

            if ( $res->{data}->{next} ) {
                $get->( $res->{data}->{next}, __SUB__ );
            }
            else {
                $cb->( result 200, $milestones );
            }
        }

        return;
    };

    $get->( "https://api.bitbucket.org/2.0/repositories/@{[$self->id]}/milestones", $process );

    return;
}

# https://confluence.atlassian.com/bitbucket/issues-resource-296095191.html#issuesResource-POSTanewmilestone
sub create_milestone ( $self, $ver, $cb ) {
    $ver = version->parse($ver)->normal;

    P->http->post(    #
        "https://api.bitbucket.org/1.0/repositories/@{[$self->id]}/issues/milestones",
        headers => {
            AUTHORIZATION => $self->auth,
            CONTENT_TYPE  => 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body      => P->data->to_uri( { name => $ver } ),
        on_finish => sub ($res) {
            if ( !$res ) {
                if ( $res->body->$* =~ /already exists/sm ) {
                    $cb->( result 200, { name => $ver } );
                }
                else {
                    $cb->( result [ $res->status, $res->reason ] );
                }
            }
            else {
                my $data = eval { P->data->from_json( $res->body->$* ) };

                if ($@) {
                    $cb->( result [ 500, 'Error decoding content' ] );
                }
                else {
                    $cb->( result 201, $data );
                }
            }

            return;
        },
    );

    return;
}

# ISSUES
# https://confluence.atlassian.com/bitbucket/issues-resource-296095191.html#issuesResource-GETalistofissuesinarepository%27stracker
sub get_issues ( $self, @ ) {
    my $cb = $_[-1];

    my %args = (
        limit     => 50,
        sort      => 'priority',    # priority, kind, version, component, milestone
        status    => undef,
        milestone => undef,
        @_[ 1 .. $#_ - 1 ],
    );

    P->http->get(                   #
        "https://bitbucket.org/api/1.0/repositories/@{[$self->id]}/issues/?" . P->data->to_uri( \%args ),
        headers   => { AUTHORIZATION => $self->auth },
        on_finish => sub ($res) {
            if ( !$res ) {
                my $data = eval { P->data->from_json( $res->body ) };

                $cb->( result [ $res->status, $data->{error}->{message} || $res->reason ] );
            }
            else {
                my $data = eval { P->data->from_json( $res->body ) };

                if ($@) {
                    $cb->( result [ 500, 'Error decoding respnse' ] );
                }
                else {
                    my $issues;

                    for my $issue ( $data->{issues}->@* ) {
                        $issue->{api} = $self;

                        push $issues->@*, bless $issue, 'Pcore::API::Bitbucket::Issue';
                    }

                    $cb->( result 200, $issues );
                }
            }

            return;
        },
    );

    return;
}

# https://confluence.atlassian.com/bitbucket/issues-resource-296095191.html#issuesResource-GETanindividualissue
sub get_issue ( $self, $id, $cb ) {
    P->http->get(
        "https://bitbucket.org/api/1.0/repositories/@{[$self->id]}/issues/$id",
        headers   => { AUTHORIZATION => $self->auth },
        on_finish => sub ($res) {
            if ( !$res ) {
                my $data = eval { P->data->from_json( $res->body ) };

                $cb->( result [ $res->status, $data->{error}->{message} || $res->reason ] );
            }
            else {
                my $data = eval { P->data->from_json( $res->body ) };

                if ($@) {
                    $cb->( result [ 500, 'Error decoding respnse' ] );
                }
                else {
                    $data->{api} = $self;

                    $cb->( result 200, bless $data, 'Pcore::API::Bitbucket::Issue' );
                }
            }

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

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::BitBucket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
