package Pcore::Core::H;

use Pcore -export => {    #
    DEFAULT => [qw[H]],
};
use Pcore::Core::H::Cache;

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
