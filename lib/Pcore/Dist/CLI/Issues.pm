package Pcore::Dist::CLI::Issues;

use Pcore -class;
use Pcore::Util::Scalar qw[blessed];

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

# TODO sort by utc_last_updated, priority
sub run ( $self, $opt, $arg ) {
    my $issues = $self->dist->build->issues(
        id => $arg->{id},
        $opt->%*,
    );

    if ( !$issues ) {
        say 'No issues';
    }
    else {
        say sprintf '%4s  %-8s  %-9s  %-11s  %s', qw[ID PRIORITY STATUS KIND TITLE];

        if ( blessed $issues ) {
            my $issue = $issues;

            say sprintf '%4s  %-8s  %-9s  %-11s  %s', $issue->{local_id}, $issue->{priority}, $issue->{status}, $issue->{metadata}->{kind}, $issue->{title};

            say $LF, $issue->{content} || 'No content';
        }
        else {
            # TODO sort utc_created_on, utc_last_updated

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
## │    3 │ 39                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 58                   │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
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
