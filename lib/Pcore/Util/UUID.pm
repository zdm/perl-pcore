package Pcore::Util::UUID;

use Pcore;
use Data::UUID qw[];    ## no critic qw[Modules::ProhibitEvilModules]

my $uuid = Data::UUID->new;

sub str {
    return $uuid->create_str;
}

sub bin {
    return $uuid->create_bin;
}

sub hex {               ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    return substr $uuid->create_hex, 2;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::UUID - Data::UUID wrapper

=head1 SYNOPSIS

    P->uuid->str;
    P->uuid->bin;
    P->uuid->hex;

=head1 DESCRIPTION

This is Data::UUID wrapper to use with Pcore::Util interafce.

=head1 SEE ALSO

L<Data::UUID|https://metacpan.org/pod/Data::UUID>

=cut
