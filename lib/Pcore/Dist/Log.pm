package Pcore::Dist::Log;

use Pcore qw[-role];

no Pcore;

sub log ( $self, $message ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    say '[#] ' . $message;

    return;
}

sub quit ( $self, $message = undef ) {
    say '[#] ' . $message if $message;

    exit;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Log

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
