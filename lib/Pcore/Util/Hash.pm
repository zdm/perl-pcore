package Pcore::Util::Hash;

use Pcore;
use Hash::Util qw[];             ## no critic qw[Modules::ProhibitEvilModules]
use Scalar::Util qw[blessed];    ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Util::Hash::Multivalue;
use Pcore::Util::Hash::RandKey;

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

    foreach my $key ( keys %{$b} ) {
        if ( blessed( $a->{$key} ) && $a->{$key}->can('MERGE') ) {
            $a->{$key} = $a->{$key}->MERGE( $b->{$key} );
        }
        elsif ( ref( $b->{$key} ) eq 'HASH' ) {
            $a->{$key} = {} unless ( ref( $a->{$key} ) eq 'HASH' );
            _merge( $a->{$key}, $b->{$key} );
        }
        elsif ( ref( $b->{$key} ) eq 'ARRAY' ) {
            $a->{$key} = [];
            @{ $a->{$key} } = @{ $b->{$key} };
        }
        else {
            $a->{$key} = $b->{$key};
        }
    }

    return;
}

sub multivalue {
    return Pcore::Util::Hash::Multivalue->new(@_);
}

sub randkey {
    return Pcore::Util::Hash::RandKey->new;
}

1;
__END__
=pod

=encoding utf8

=cut
