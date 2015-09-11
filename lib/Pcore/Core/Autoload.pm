package Pcore::Core::Autoload;

use Pcore;
use Pcore::Core::Exporter qw[];

sub import {
    my $self = shift;

    # parse tags and pragmas
    my ( $tags, $pragma ) = Pcore::Core::Exporter::parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    no strict qw[refs];
    no warnings qw[redefine];

    *{ $caller . '::AUTOLOAD' } = \&_AUTOLOAD;

    return;
}

sub _AUTOLOAD {
    my $self = $_[0];

    die qq["autoload" method is required in "$self" by "-autoload" pragma] unless $self->can('autoload');

    my $method = our $AUTOLOAD =~ s/\A.*:://smr;

    my $class = ref $self || $self;

    # request CODEREF
    my ( $code, %args ) = $self->autoload( $method, @_ );

    # install returned coderef as method
    if ( !$args{not_create_method} ) {
        no strict qw[refs];

        *{ $class . q[::] . $method } = $code;
    }

    goto &{$code};
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Autoload

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
