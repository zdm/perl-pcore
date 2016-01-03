package Pcore::Dist::CLI::Deploy;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub cli_abstract ($self) {
    return 'deploy distribution';
}

sub cli_opt ($self) {
    return {
        all        => { desc => 'implies --develop, --recommends and --suggeests', },
        install    => { desc => 'install bin/ to PATH and lib/ to PERL5LIB', },
        develop    => { desc => 'cpanm --with-develop', },
        recommends => { desc => 'cpanm --with-recommends', },
        suggests   => { desc => 'cpanm --with-suggests', },
        verbose    => { desc => 'cpanm --verbose', },
    };
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run($opt);

    return;
}

sub run ( $self, $args ) {
    $self->dist->build->deploy( $args->%* );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 29                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Deploy - deploy distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
