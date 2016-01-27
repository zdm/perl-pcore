package Pcore::Dist::CLI::Smoke;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'smoke your distribution',
        opt      => {
            author => {
                desc    => 'enables the AUTHOR_TESTING env variable (default behavior)',
                default => 0,
            },
            release => {
                desc    => 'enables the RELEASE_TESTING env variable',
                default => 0,
            },
            all => {    #
                short => undef,
                desc  => 'enables the RELEASE_TESTING, AUTOMATED_TESTING and AUTHOR_TESTING env variables',
            },
            jobs => {
                desc => 'number of parallel test jobs to run',
                isa  => 'PositiveInt',
            },
            verbose => { desc => 'enables verbose testing (TEST_VERBOSE env variable on Makefile.PL, --verbose on Build.PL' },
        },
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    $self->new->run($opt);

    return;
}

sub run ( $self, $args ) {
    exit 3 if !$self->dist->build->test( $args->%*, smoke => 1 );

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
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Smoke - smoke your distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
