package Pcore::Dist::CLI::Wiki;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'generate wiki pages',
        opt      => {
            clone => {
                desc    => 'clone wiki repository from upstream',
                default => 0,
            },
        },
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    $self->new->run;

    return;
}

sub run ($self) {
    if ( !$self->dist->build->wiki ) {
        say 'Wiki was not found' . $LF;

        exit 3;
    }

    $self->dist->build->wiki->run;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 32                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Wiki - generate wiki pages

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
