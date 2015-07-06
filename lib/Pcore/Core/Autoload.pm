package Pcore::Core::Autoload;

use Pcore;
use Pcore::Core::Autoload::Package;

sub import {
    my $self = shift;

    # parse tags and pragmas
    my ( $tags, $pragma ) = Pcore::Core::Exporter::Helper->parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    # install @ISA relationship
    {
        no strict qw[refs];

        push @{ $caller . '::ISA' }, 'Pcore::Core::Autoload::Package' unless 'Pcore::Core::Autoload::Package' ~~ @{ $caller . '::ISA' };
    }

    return;
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
