package Pcore::Util::Scalar;

use Pcore -export, [qw[blessed refaddr reftype weaken isweak looks_like_number is_hash is_array is_glob]];
use Scalar::Util qw[blessed dualvar isdual readonly refaddr reftype tainted weaken isweak isvstring looks_like_number set_prototype];    ## no critic qw[Modules::ProhibitEvilModules]

sub is_hash {
    return ( reftype( $_[0] ) // q[] ) eq 'HASH' ? 1 : 0;
}

sub is_array {
    return ( reftype( $_[0] ) // q[] ) eq 'ARRAY' ? 1 : 0;
}

sub is_glob {
    return 1 if eval {
        local $SIG{__DIE__} = undef;

        $_[0]->isa('GLOB') || $_[0]->isa('IO');
    };

    return 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Scalar

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
