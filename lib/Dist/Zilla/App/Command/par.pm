package Dist::Zilla::App::Command::par;

use strict;
use warnings;
use utf8;
use Dist::Zilla::App qw[-command];

sub abstract {
    my ($self) = @_;

    return 'build PAR executable (Pcore)';
}

sub opt_spec {
    my ( $self, $app ) = @_;

    return
      [ release => 'build release binary' ],
      [ crypt   => 'crypt non-core perl sources with Filter::Crypto' ],
      [ noupx   => 'do not compress shared objects with upx' ],
      [ clean   => 'clean temp dir on exit' ];
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    # NOTE args is just raw array or params, that not described as options

    die 'no args expected' if @{$args};

    return;
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    if ( !$INC{'Pcore.pm'} ) {
        print qq[Pcore is required to run this command\n];

        return;
    }

    $self->zilla->plugin_named('PAR')->build_par(
        release => $opt->release,
        crypt   => $opt->crypt,
        noupx   => $opt->noupx,
        clean   => $opt->clean,
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 8                    │ NamingConventions::ProhibitAmbiguousNames - Ambiguously named subroutine "abstract"                            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 29                   │ ErrorHandling::RequireCarping - "die" used instead of "croak"                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 1                    │ Modules::RequireVersionVar - No package-scoped "$VERSION" variable found                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 1                    │ NamingConventions::Capitalization - Package "Dist::Zilla::App::Command::par" does not start with a upper case  │
## │      │                      │ letter                                                                                                         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 38                   │ InputOutput::RequireCheckedSyscalls - Return value of flagged function ignored - print                         │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
