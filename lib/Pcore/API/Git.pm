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

sub run ( $self, $cmd, $root = undef, $cb = undef ) {
    state $run = sub ( $self, $cmd, $root, $cb ) {
        my $proc = P->sys->run_proc(
            [ is_plain_arrayref $cmd ? ( 'git', $cmd->@* ) : 'git ' . $cmd ],
            chdir  => $root || $self->{root},
            stdout => 1,
            stderr => 1,
        );

        $proc->capture->wait;

        my $res;

        if ( $proc->is_success ) {
            $res = res 200, $proc->{stdout} ? [ split /\x00/sm, $proc->{stdout}->$* ] : undef;
        }
        else {
            $res = res [ 500, $proc->{stderr} ? ( $proc->{stderr}->$* =~ /\A(.+?)\n/sm )[0] : () ];
        }

        return $cb ? $cb->($res) : $res;
    };

    if ( defined wantarray ) {
        return $run->( $self, $cmd, $root, $cb );
    }
    else {
        Coro::async {
            $run->( $self, $cmd, $root, $cb );

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

# -------------------------
sub git_has_upstream ($self) {
    return;
}

sub git_clone_url ( $self, $url_type = $GIT_UPSTREAM_URL_SSH ) {

    # ssh
    if ( $url_type == $GIT_UPSTREAM_URL_SSH ) {
        return "git\@$GIT_UPSTREAM_HOST->{$self->{upstream}}:$self->{repo_id}.git";
    }

    # https
    else {
        return "https://$GIT_UPSTREAM_HOST->{$self->{upstream}}/$self->{repo_id}.git";
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 119                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
