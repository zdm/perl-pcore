package Pcore::Util::Hash;

use Pcore;
use Hash::Util qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Util::Scalar qw[is_blessed_ref];

sub merge {
    my $res = defined wantarray ? {} : shift;

    for my $hash_ref (@_) {
        _merge( $res, $hash_ref );
    }

    return $res;
}

sub _merge {
    my $a = shift;
    my $b = shift;

    for my $key ( keys $b->%* ) {
        if ( is_blessed_ref $a->{$key} && $a->{$key}->can('MERGE') ) {
            $a->{$key} = $a->{$key}->MERGE( $b->{$key} );
        }
        elsif ( ref( $b->{$key} ) eq 'HASH' ) {
            $a->{$key} = {} unless ref $a->{$key} eq 'HASH';

            _merge( $a->{$key}, $b->{$key} );
        }
        elsif ( ref $b->{$key} eq 'ARRAY' ) {
            $a->{$key} = [];

            $a->{$key}->@* = $b->{$key}->@*;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
        }
        else {
            $a->{$key} = $b->{$key};
        }
    }

    return;
}

sub multivalue {
    state $init = !!require Pcore::Util::Hash::Multivalue;

    return Pcore::Util::Hash::Multivalue->new(@_);
}

sub randkey {
    state $init = !!require Pcore::Util::Hash::RandKey;

    return Pcore::Util::Hash::RandKey->new;
}

sub limited ($max_size) {
    state $init = !!require Pcore::Util::Hash::LRU;

    return Pcore::Util::Hash::LRU->new($max_size);
}

1;
__END__
=pod

=encoding utf8

=cut
