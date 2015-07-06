package Pcore::Core::EV;

use Pcore qw[-export];
use Pcore::Core::EV::Queue;

our @EXPORT_OK   = qw[EV];
our %EXPORT_TAGS = (         #
    CORE => \@EXPORT_OK
);
our @EXPORT = qw[];

sub EV {
    state $EV = Pcore::Core::EV::Queue->new;

    return $EV;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::EV

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
