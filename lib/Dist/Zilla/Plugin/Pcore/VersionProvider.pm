package Dist::Zilla::Plugin::Pcore::VersionProvider;

use Moose;
use Pcore;

with qw[Dist::Zilla::Role::VersionProvider];

no Pcore;
no Moose;

sub provide_version ( $self, @ ) {
    my $main_module = $self->zilla->main_module;

    my $ver;

    if ( $main_module->encoded_content =~ m[^\s*package\s+\w[\w\:\']*\s+(v?[0-9._]+)\s*;]sm ) {
        $ver = $1;
    }
    else {
        $ver = v0.1.0;
    }

    if ( $ENV{DZIL_RELEASING} ) {
        say q[Current version: ] . $ver;

        my $defver = version->new($ver);

        $defver->{version}->[2]++;

      REDO:
        my $rver = $defver->normal;

        print qq[Enter release version [$rver]: ];

        my $in = <$STDIN>;

        chomp $in;

        if ($in) {
            $rver = eval { version->new($in) };

            if ( $@ || $rver <= $ver ) {
                say 'Invalid version format';

                goto REDO;
            }
        }

        $ver = $rver;
    }

    return $ver;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 16                   │ RegularExpressions::ProhibitEnumeratedClasses - Use named character classes ([0-9] vs. \d)                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Dist::Zilla::Plugin::Pcore::VersionProvider

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
