package Pcore::Core::EV;

use Pcore -export => {    #
    CORE => [qw[EV]],
};
use Pcore::Core::EV::Queue;

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
