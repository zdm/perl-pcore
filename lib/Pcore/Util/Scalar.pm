package Pcore::Util::Scalar;

use Pcore -autoload;
use Scalar::Util qw[];    ## no critic qw[Modules::ProhibitEvilModules]

sub is_hash {
    my $self = shift;

    return ( $self->reftype( $_[0] ) // q[] ) eq 'HASH' ? 1 : 0;
}

sub is_array {
    my $self = shift;

    return ( $self->reftype( $_[0] ) // q[] ) eq 'ARRAY' ? 1 : 0;
}

sub is_glob {
    my $self = shift;

    if ( eval { $_[0]->isa('GLOB') || $_[0]->isa('IO') } ) {
        return 1;
    }

    return 0;
}

sub autoload {
    my $self   = shift;
    my $method = shift;

    my $sub_name = 'Scalar::Util::' . $method;

    return sub {
        my $self = shift;

        goto &{$sub_name};
    };
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
