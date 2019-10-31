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

around new => sub ( $orig, $self, $path, $search = undef ) {
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

sub git_run ( $self, $cmd, $cb = undef ) {
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
sub git_init ( $self, $path ) {
    my $res = P->sys->run_proc( qq[git init -q "$path"], stdout => 1, stderr => 1 )->wait;

    return $res;
}

# TODO
sub git_clone ( $self, $from, $to ) {
    return;
}

# TODO
sub upstream ($self) {
    require Pcore::API::Git::Upstream;

    return;
}

sub git_id ( $self, $cb = undef ) {

    # get all tags - git tag --points-at HEAD
    # get current branch git branch --show-current
    # git rev-parse --short HEAD
    # git rev-parse HEAD
    # git branch --no-color --contains HEAD

    my $res1 = res 200,
      { branch           => undef,
        date             => undef,
        id               => undef,
        id_short         => undef,
        is_dirty         => undef,
        release          => undef,
        release_distance => undef,
        tags             => undef,
      };

    my $cv = P->cv->begin( sub ($cv) {
        $cv->( $cb ? $cb->($res1) : $res1 );

        return;
    } );

    $cv->begin;
    $self->git_run(
        'log -1 --pretty=format:%H%n%h%n%cI%n%D',
        sub ($res) {
            $cv->end;

            return if !$res1;

            if ( !$res ) {
                $res1 = $res;
            }
            else {
                ( my $data->@{qw[id id_short date]}, my $ref ) = split /\n/sm, $res->{data};

                my @ref = split /,/sm, $ref;

                # parse current branch
                if ( ( shift @ref ) =~ /->\s(.+)/sm ) {
                    $data->{branch} = $1;
                }

                # parse tags
                for my $token (@ref) {
                    if ( $token =~ /tag:\s(.+)/sm ) {
                        $data->{tags}->{$1} = 1;
                    }
                }

                $res1->{data}->@{ keys $data->%* } = values $data->%*;
            }

            return;
        },
    );

    $cv->begin;
    $self->git_run(
        'describe --tags --always --match "v[0-9]*.[0-9]*.[0-9]*"',
        sub ($res) {
            $cv->end;

            return if !$res1;

            if ( !$res ) {
                $res1 = $res;
            }
            else {

                # remove trailing "\n"
                chomp $res->{data};

                my @data = split /-/sm, $res->{data};

                if ( $data[0] =~ /\Av\d+[.]\d+[.]\d+\z/sm ) {
                    $res1->{data}->{release} = $data[0];

                    $res1->{data}->{release_distance} = $data[1] || 0;
                }
            }

            return;
        },
    );

    $cv->begin;
    $self->git_run(
        'status --porcelain',
        sub ($res) {
            $cv->end;

            return if !$res1;

            if ( !$res ) {
                $res1 = $res;
            }
            else {
                $res1->{data}->{is_dirty} = 0+ !!$res->{data};
            }

            return;
        },
    );

    if ( defined wantarray ) {
        return $cv->end->recv;
    }
    else {
        return;
    }
}

sub git_releases ( $self, $cb = undef ) {
    return $self->git_run(
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
    return $self->git_run(
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

sub git_is_pushed ( $self, $cb = undef ) {
    return $self->git_run(
        'branch -v --no-color',
        sub ($res) {
            if ($res) {
                my $data;

                for my $br ( split /\n/sm, $res->{data} ) {
                    if ( $br =~ /\A[*]?\s+(.+?)\s+(?:.+?)\s+(?:\[ahead\s(\d+)\])?/sm ) {
                        $data->{$1} = $2 || 0;
                    }
                    else {
                        die qq[Can't parse branch: $br];
                    }

                    $res->{data} = $data;
                }
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
