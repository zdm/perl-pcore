package Pcore::Dist::CLI::Issues;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub cli_abstract ($self) {
    return 'view project issues';
}

sub cli_opt ($self) {
    return {
        active    => { desc  => 'new, open, resolved, closed' },
        new       => { desc  => 'status "new" + "open"' },
        open      => { desc  => 'status "new" + "open"' },
        resolved  => { desc  => 'status "resolved"' },
        closed    => { desc  => 'status "closed"' },
        hold      => { short => 'H', desc => 'status "on hold"' },
        invalid   => { desc  => 'status "invalid"' },
        duplicate => { desc  => 'status "duplicate"' },
        wontfix   => { desc  => 'status "wonfix"' },
    };
}

sub cli_arg ($self) {
    return [
        {   name => 'id',
            desc => 'issue ID',
            isa  => 'PositiveInt',
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

        if ( $arg->{id} && $opt->%* ) {

            # issue status changed, show only issue header, without content
            if ($issues) {
                $self->dist->build->issues->print_issues( $issues, 0 );
            }
            else {
                say 'Error update issue status';
            }
        }
        else {
            $self->dist->build->issues->print_issues( $issues, 1 );
        }
    }
    else {
        say 'No issues';
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
## │    3 │ 45, 48               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 43, 52, 59           │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
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
