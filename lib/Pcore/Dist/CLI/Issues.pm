package Pcore::Dist::CLI::Issues;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub cli_abstract ($self) {
    return 'view project issues';
}

sub cli_opt ($self) {
    return {    #
        opened   => { desc => 'status "open"',     default => 0 },
        resolved => { desc => 'status "resolved"', default => 0 },
        closed   => { desc => 'status "closed"',   default => 0 },
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
    $self->new->run($opt);

    return;
}

sub run ( $self, $opt ) {
    state $init = !!require Pcore::API::Bitbucket;

    my $scm = $self->dist->scm;

    my $bb = Pcore::API::Bitbucket->new(
        {   account_name => $scm->upstream->username,
            repo_slug    => $scm->upstream->reponame,
            username     => $self->dist->build->user_cfg->{Bitbucket}->{api_username},
            password     => $self->dist->build->user_cfg->{Bitbucket}->{api_password},
        }
    );

    my $cv = AE::cv;

    my $status;

    if ( $opt->{opened} ) {
        $status = 'opened';
    }
    elsif ( $opt->{resolved} ) {
        $status = 'resolved';
    }
    elsif ( $opt->{closed} ) {
        $status = 'closed';
    }
    else {
        $status = 'opened';
    }

    my $issues;

    $bb->issues(
        version   => undef,
        milestone => undef,
        status    => $status,
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
        say sprintf '%4s  %-9s  %s', qw[ID STATUS TITLE];

        for my $issue ( sort { $a->{local_id} <=> $b->{local_id} } values $issues->%* ) {
            say sprintf '%4s  %-9s  %s', $issue->{local_id}, $issue->{status}, $issue->{title};
        }
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 87                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 40                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
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
