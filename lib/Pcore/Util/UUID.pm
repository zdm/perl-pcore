package Pcore::Util::UUID;

use Pcore -export => { ALL => [qw[uuid_bin uuid_str uuid_hex create_uuid create_uuid_from_bin create_uuid_from_str create_uuid_from_hex]] };
use Pcore::Util::UUID::Obj;
use Data::UUID qw[];    ## no critic qw[Modules::ProhibitEvilModules]

our $UUID = Data::UUID->new;

*create_uuid          = \&create;
*create_uuid_from_bin = \&create_from_bin;
*create_uuid_from_str = \&create_from_str;
*create_uuid_from_hex = \&create_from_hex;

*uuid_bin = \&bin;
*uuid_str = \&str;
*uuid_hex = \&hex;

sub create {
    return bless { bin => $UUID->create_bin }, 'Pcore::Util::UUID::Obj';
}

sub create_from_bin ($bin) {
    return bless { bin => $bin }, 'Pcore::Util::UUID::Obj';
}

sub create_from_str ($str) {
    return bless { str => $str }, 'Pcore::Util::UUID::Obj';
}

sub create_from_hex ($hex) {
    return bless { hex => $hex }, 'Pcore::Util::UUID::Obj';
}

sub bin {
    return $UUID->create_bin;
}

sub str {
    return $UUID->create_str;
}

sub hex {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    return $UUID->create_hex;
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
