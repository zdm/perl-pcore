package Pcore::API::Git;

use Pcore -class, -res, -const, -export;
use Pcore::Lib::Scalar qw[is_plain_arrayref];

has root => ( required => 1 );

has _upstream => ( init_arg => undef );
has upstream  => ( init_arg => undef );

# TODO https://metacpan.org/release/App-IsGitSynced/source/bin/is_git_synced

our $EXPORT = {
    GIT_UPSTREAM_URL => [qw[$GIT_UPSTREAM_URL_HTTPS $GIT_UPSTREAM_URL_SSH]],
    GIT_UPSTREAM     => [qw[$GIT_UPSTREAM_BITBUCKET $GIT_UPSTREAM_GITHUB $GIT_UPSTREAM_GITLAB]],
};

const our $GIT_UPSTREAM_URL_HTTPS => 1;
const our $GIT_UPSTREAM_URL_SSH   => 2;

const our $GIT_UPSTREAM_BITBUCKET => 1;
const our $GIT_UPSTREAM_GITHUB    => 2;
const our $GIT_UPSTREAM_GITLAB    => 3;

const our $GIT_UPSTREAM_HOST => {
    $GIT_UPSTREAM_BITBUCKET => 'bitbucket.org',
    $GIT_UPSTREAM_GITHUB    => 'github.com',
    $GIT_UPSTREAM_GITLAB    => 'gitlab.com',
};

around new => sub ( $orig, $self, $path, $search = 1 ) {
    $path = P->path($path)->to_abs;

    my $found;

    if ( -d "$path/.git" ) {
        $found = 1;
    }
    elsif ($search) {
        $path = $path->parent;

        while ($path) {
            if ( -d "$path/.git" ) {
                $found = 1;

                last;
            }

            $path = $path->parent;
        }
    }

    return $self->$orig( { root => $path } ) if $found;

    return;
};

sub run ( $self, $cmd, $cb = undef ) {
    state $run = sub ( $self, $cmd, $cb ) {
        my $proc = P->sys->run_proc(
            [ is_plain_arrayref $cmd ? ( 'git', $cmd->@* ) : 'git ' . $cmd ],
            chdir  => $self->{root},
            stdout => 1,
            stderr => 1,
        );

        $proc->capture->wait;

        my $res;

        if ( $proc->is_success ) {
            $res = res 200, $proc->{stdout} ? $proc->{stdout}->$* : undef;
        }
        else {
            $res = res [ 500, $proc->{stderr} ? $proc->{stderr}->$* : $EMPTY ];
        }

        return $cb ? $cb->($res) : $res;
    };

    if ( defined wantarray ) {
        return $run->( $self, $cmd, $cb );
    }
    else {
        Coro::async {
            $run->( $self, $cmd, $cb );

            return;
        };
    }

    return;
}

# TODO
sub init ( $self, $path ) {
    my $res = P->sys->run_proc( qq[git init -q "$path"], stdout => 1, stderr => 1 )->wait;

    return $res;
}

# TODO
sub clone ( $self, $from, $to ) {
    return;
}

# TODO
sub upstream ($self) {
    require Pcore::API::Git::Upstream;

    return;
}

# TODO branch, hash, tags, date, latest_release_tag, release_distance
sub git_id ($self) {

    return;
}

sub git_releases ( $self, $cb = undef ) {
    return $self->run(
        'tag --merged master',
        sub ($res) {
            if ($res) {
                $res->{data} = [ sort grep {/\Av\d+[.]\d+[.]\d+\z/sm} split /\n/sm, $res->{data} ];
            }

            return $cb ? $cb->($res) : $res;
        },
    );
}

# TODO
sub git_get_changesets ( $self, $tag = undef, $cb = undef ) {
    return $self->scm_cmd(
        [ $tag ? ( 'log', '-r', "$tag:" ) : 'log' ],
        sub ($res) {
            if ($res) {
                my $data;

                for my $line ( $res->{data}->@* ) {
                    my $changeset = {};

                    for my $field ( split /\n/sm, $line ) {
                        my ( $k, $v ) = split /:\s+/sm, $field, 2;

                        if ( exists $changeset->{$k} ) {
                            if ( is_plain_arrayref $changeset->{$k} ) {
                                push $changeset->{$k}->@*, $v;
                            }
                            else {
                                $changeset->{$k} = [ $changeset->{$k}, $v ];
                            }
                        }
                        else {
                            $changeset->{$k} = $v;
                        }
                    }

                    push $data->@*, $changeset;
                }

                $res->{data} = $data;
            }

            return $cb ? $cb->($res) : $res;
        },
    );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Git

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
