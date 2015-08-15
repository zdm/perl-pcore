package Pcore::Util::Hash;

use Pcore qw[-autoload];
use Hash::Util qw[];      ## no critic qw[Modules::ProhibitEvilModules]
use Scalar::Util qw[];    ## no critic qw[Modules::ProhibitEvilModules]

sub autoload {
    my $self   = shift;
    my $method = shift;

    my $sub_name = 'Hash::Util::' . $method;

    return sub {
        my $self = shift;

        goto &{$sub_name};
    };
}

sub merge {
    my $self = shift;
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
        if ( Scalar::Util::blessed( $a->{$key} ) && $a->{$key}->can('MERGE') ) {
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
    my $self = shift;

    require Pcore::Util::Hash::Multivalue;

    return Pcore::Util::Hash::Multivalue->new(@_);
}

sub rand_key {
    my $self     = shift;
    my $hash_ref = shift;

    return [ keys %{$hash_ref} ]->[ rand keys %{$hash_ref} ];
}

1;
__END__
=pod

=encoding utf8

=cut
