package Pcore::Core::H;

use Pcore qw[-export];
use Pcore::Core::H::Cache;

our @EXPORT_OK   = qw[H];
our %EXPORT_TAGS = ();
our @EXPORT      = qw[H];

sub H {
    state $H = Pcore::Core::H::Cache->new;

    return $H;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::H

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
