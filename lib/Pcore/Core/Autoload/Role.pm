package Pcore::Core::Autoload::Role;

use Pcore qw[-role];

# requires qw[autoload]; # cause of "Segmentation fault" unless required method was found

sub AUTOLOAD ( $self, @ ) {    ## no critic qw(ClassHierarchies::ProhibitAutoloading)
    my $method = our $AUTOLOAD =~ s/\A.*:://smr;

    my $class = ref $self || $self;

    # request CODEREF
    my ( $code, %args ) = $self->autoload( $method, @_ );

    # install returned coderef as method
    if ( !$args{not_create_method} ) {
        no strict qw[refs];

        *{ $class . q[::] . $method } = $code;

        P->class->set_subname( $class . qq[::$method(AUTOLOAD)] => $code );
    }

    goto &{$code};
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Autoload::Role

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
