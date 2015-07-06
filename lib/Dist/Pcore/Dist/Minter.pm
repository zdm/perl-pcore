package Dist::Pcore::Dist::Minter;

use Pcore qw[-class];
use Path::Class qw[dir];

extends qw[Dist::Zilla::Dist::Minter];

no Pcore;

sub _mint_target_dir {
    my ($self) = @_;

    my $dir = dir( lc $self->name );

    $self->log_fatal("$dir already exists") if -e $dir;

    return $dir->absolute;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 10                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_mint_target_dir' declared but not  │
## │      │                      │ used                                                                                                           │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Dist::Pcore::Dist::Minter

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
