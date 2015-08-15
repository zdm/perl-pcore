package Pcore::Util::UUID;

use Pcore;
use Data::UUID qw[];    ## no critic qw[Modules::ProhibitEvilModules]

sub str {
    my $self = shift;

    return Data::UUID->new->create_str;
}

sub bin {
    my $self = shift;

    return Data::UUID->new->create_bin;
}

sub hex {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my $self = shift;

    return substr Data::UUID->new->create_hex, 2;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::UUID

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
