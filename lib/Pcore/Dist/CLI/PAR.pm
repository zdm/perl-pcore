package Pcore::Dist::CLI::PAR;

use Pcore qw[-class];

with qw[Pcore::Dist::CLI];

no Pcore;

sub cli_opt ($self) {
    return {
        release => { desc => 'build release binary', },
        crypt   => {
            desc    => 'crypt non-core perl sources with Filter::Crypto',
            negated => 1,
        },
        upx => {
            desc    => 'do not compress shared objects with upx',
            negated => 1,
        },
        clean => {
            desc    => 'clean temp dir on exit',
            negated => 1,
        },
    };
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run($opt);

    return;
}

sub run ( $self, $opt ) {
    $self->dist->build->par( $opt->%* );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 34                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::PAR - build PAR executable

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
