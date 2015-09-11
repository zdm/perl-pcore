package Pcore::Core::Exporter;

use Pcore;
use Exporter::Heavy qw[];

sub import {
    my $self = shift;

    # parse tags and pragmas
    my ( $tags, $pragma ) = parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    no strict qw[refs];    ## no critic qw[TestingAndDebugging::ProhibitProlongedStrictureOverride]
    no warnings qw[redefine];

    *{ $caller . '::import' } = \&_import;

    *{ $caller . '::unimport' } = \&_unimport;

    return;
}

sub _import {
    my $self = shift;

    # parse tags and pragmas
    my ( $tags, $pragma ) = parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    # call Exporter
    Exporter::Heavy::heavy_export( $self, $caller, @{$tags} );

    return;
}

sub _unimport {
    my $self = shift;

    # parse tags and pragmas
    my ( $tags, $pragma ) = parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    return if $self eq $caller;    # protection from unimport from mysqlf

    no strict qw[refs];

    # unimport all symbols, declared in @EXPORT_OK
    # NOTE only subroutines can be unimported right now
    for ( @{ $self . '::EXPORT_OK' } ) {
        delete ${ $caller . q[::] }{$_};
    }

    return;
}

sub parse_import {
    my $caller = shift;

    my $tags = [];

    my $pragma = {};

    my $data;

    while ( my $arg = shift ) {
        if ( ref $arg eq 'HASH' ) {
            $data = $arg;
        }
        elsif ( $arg =~ /\A-(.+)\z/sm ) {
            if ( $1 eq 'level' || $1 eq 'caller' ) {
                $pragma->{$1} = shift;
            }
            elsif ( exists ${ $caller . '::EXPORT_PRAGMAS' }{$1} ) {
                $pragma->{$1} = ${ $caller . '::EXPORT_PRAGMAS' }{$1} ? shift : 1;
            }
            else {
                die qq[Unknown exporter pragma found "$arg" while importing package "$caller"];
            }

        }
        else {
            push @{$tags}, $arg;
        }
    }

    return $tags, $pragma, $data;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Exporter - standard perl Exporter wrapper

=head1 SYNOPSIS

    use Pcore::Core::Exporter qw[];

    Pcore::Core::Exporter->import( -caller => 'Some::Package' ); # install import methos to target package

    Pcore::Core::Exporter->import( -level => 1 ); # install import methos to package in call stack

=head1 DESCRIPTION

See Exporter documentation for how to use exporting tags.

@EXPORT - contains symbols, that exported by default.

@EXPORT_OK - contains symbols, that can be exported by request.

%EXPORT_TAGS - Hash[ArrayRef] of tags and appropriate symbols.

%EXPORT_PRAGMAS - hash of pragmas, supported by exporter package. Pragmas "-level" and "-caller" are added automatically.

@EXPORT symbols are exported only if used explicitly, or if no other imports specified. If first tag is negated (!tag) - @EXPORT will be implied automatically.

=cut
