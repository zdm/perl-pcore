package Pcore::Dist::CLI::Issues;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub cli_abstract ($self) {
    return 'view project issues';
}

sub cli_opt ($self) {
    return {
        all      => { desc => 'status "new" + "open" + "resolved" + "closed"', default => 0 },
        open     => { desc => 'status "new" + "open"',                         default => 0 },
        resolved => { desc => 'status "resolved"',                             default => 0 },
        closed   => { desc => 'status "closed"',                               default => 0 },
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
    if ( $self->dist->build->issues ) {
        my $issues = $self->dist->build->issues->get(
            id => $arg->{id},
            $opt->%*,
        );

        $self->dist->build->issues->print_issues($issues);
    }
    else {
        say 'No issues';
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
## │    2 │ 37, 42               │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
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
