package Pcore::Core::Exporter;

use Pcore;
use Exporter::Heavy qw[];
use Pcore::Core::Exporter::Helper;

sub import {
    my $self = shift;

    # parse tags and pragmas
    my ( $tags, $pragma ) = Pcore::Core::Exporter::Helper->parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    return if $self eq $caller;    # protection from re-export to myself

    # call Exporter
    Exporter::Heavy::heavy_export( $self, $caller, @{$tags} );

    return;
}

sub unimport {                     ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my $self = shift;

    # parse tags and pragmas
    my ( $tags, $pragma ) = Pcore::Core::Exporter::Helper->parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    return if $self eq $caller;    # protection from unimport from mysqlf

    # unimport all symbols, declared in @EXPORT_OK
    for ( @{ $self . '::EXPORT_OK' } ) {
        delete ${ $caller . q[::] }{$_};
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Exporter - standard perl Exporter wrapper

=head1 SYNOPSIS

    use Pcore qw[-level => 2]; # export to package, next to caller

    use Pcore qw[-caller => 'Package::To::Export::To']; # export symbols to specified package

=head1 DESCRIPTION

See Exporter documentation for how to use exporting tags.

@EXPORT - contains symbols, that exported by default.

@EXPORT_OK - contains symbols, that can be exported by request.

%EXPORT_TAGS - Hash[ArrayRef] of tags and appropriate symbols.

%EXPORT_PRAGMAS - hash of pragmas, supported by exporter package. Pragmas "-level" and "-caller" are added automatically.

@EXPORT symbols are exported only if used explicitly, or if no other imports specified. If first tag is negated (!tag) - @EXPORT will be implied automatically.

=cut
