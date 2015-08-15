package Pcore::Util::Capture;

use Pcore;
use Capture::Tiny qw[:all];    ## no critic qw[Modules::ProhibitEvilModules]

sub sys {
    my $self = shift;
    my @args = @_;

    return capture_merged {
        P->sys->system(@args);
    };
}

sub code {
    my $self = shift;
    my $code = shift;

    return &Capture::Tiny::capture_merged($code);    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

1;
__END__
=pod

=encoding utf8

=cut
