package Pcore::Dist::CLI::Issues;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub cli_abstract ($self) {
    return 'view project issues';
}

sub cli_opt ($self) {
    return {    #
        open     => { desc => 'status "new" + "open"', default => 0 },
        resolved => { desc => 'status "resolved"',     default => 0 },
        closed   => { desc => 'status "closed"',       default => 0 },
    };
}

sub cli_arg ($self) {
    return [
        {   name => 'id',
            desc => 'issue ID',
            min  => 0,
        },
    ];
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run( $opt, $arg );

    return;
}

sub run ( $self, $opt, $arg ) {
    state $init = !!require Pcore::API::Bitbucket;

    my $scm = $self->dist->scm;

    my $bb = Pcore::API::Bitbucket->new(
        {   account_name => $scm->upstream->username,
            repo_slug    => $scm->upstream->reponame,
            username     => $self->dist->build->user_cfg->{Bitbucket}->{api_username},
            password     => $self->dist->build->user_cfg->{Bitbucket}->{api_password},
        }
    );

    my $id = $arg->{id};

    my $cv = AE::cv;

    my $status;

    if ( $opt->{open} ) {
        $status = [ 'new', 'open' ];
    }
    elsif ( $opt->{resolved} ) {
        $status = 'resolved';
    }
    elsif ( $opt->{closed} ) {
        $status = 'closed';
    }
    else {
        $status = [ 'new', 'open' ];
    }

    my $issues;

    $bb->issues(
        id        => $id,
        status    => $status,
        version   => undef,
        milestone => undef,
        sub ($res) {
            $issues = $res;

            $cv->send;

            return;
        }
    );

    $cv->recv;

    if ( !$issues ) {
        say 'No issues';
    }
    else {
        say sprintf '%4s  %-8s  %-9s  %-11s  %s', qw[ID PRIORITY STATUS KIND TITLE];

        if ($id) {
            my $issue = $issues;

            say sprintf '%4s  %-8s  %-9s  %-11s  %s', $issue->{local_id}, $issue->{priority}, $issue->{status}, $issue->{metadata}->{kind}, $issue->{title};
            say $LF, $issues->{content};
        }
        else {
            for my $issue ( sort { $b->priority_id <=> $a->priority_id } $issues->@* ) {
                say sprintf '%4s  %-8s  %-9s  %-11s  %s', $issue->{local_id}, $issue->{priority}, $issue->{status}, $issue->{metadata}->{kind}, $issue->{title};
            }
        }
    }

    say q[];

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 40                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 97                   │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Issues

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
