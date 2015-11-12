package Pcore::Dist::Config;

use Pcore qw[-role];

has user_cfg => ( is => 'lazy', isa => Maybe [HashRef], init_arg => undef );

no Pcore;

sub _build_user_cfg ($self) {
    if ( my $home = $ENV{HOME} || $ENV{USERPROFILE} ) {
        if ( -f $home . '/.pcore/config.ini' ) {
            return P->cfg->load( $home . '/.pcore/config.ini' );
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
## │    3 │ 11                   │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Config

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
