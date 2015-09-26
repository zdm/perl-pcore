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

    if ( !defined ${ $self . '::__EXPORT_PROCESSED__' } ) {
        no strict qw[refs];    ## no critic qw[TestingAndDebugging::ProhibitProlongedStrictureOverride]

        ${ $self . '::__EXPORT_PROCESSED__' } = 1;

        # create %EXPORT_TAGS
        *{ $self . '::EXPORT_TAGS' } = {} if !defined *{ $self . '::EXPORT_TAGS' }{HASH};

        my %export_ok = ();

        # index @EXPORT_OK
        if ( defined *{ $self . '::EXPORT_OK' }{ARRAY} ) {
            for my $export ( @{ *{ $self . '::EXPORT_OK' } } ) {
                die qq[\@EXPORT_OK can't contain tags in %$self\::EXPORT_OK] if index( $export, q[:] ) == 0;

                $export_ok{$export} = 1;
            }
        }

        # :ALL tag will be created automatically later
        delete ${ $self . '::EXPORT_TAGS' }{ALL};

        # index @EXPORT_TAGS
        for my $tag ( keys %{ $self . '::EXPORT_TAGS' } ) {
            my %tag_export = ();

            for my $tag_export ( @{ ${ $self . '::EXPORT_TAGS' }{$tag} } ) {
                if ( index( $tag_export, q[:] ) == 0 ) {    # included tag found
                    die qq[Export tags can't contain other tags in %$self\::EXPORT_TAGS];
                }
                else {
                    $tag_export{$tag_export} = 1;

                    $export_ok{$tag_export} = 1;
                }
            }

            # set tag exports
            ${ $self . '::EXPORT_TAGS' }{$tag} = [ keys %tag_export ];
        }

        # set @EXPORT_OK
        *{ $self . '::EXPORT_OK' } = [ keys %export_ok ];

        # set :ALL tag
        ${ $self . '::EXPORT_TAGS' }{ALL} = *{ $self . '::EXPORT_OK' }{ARRAY};

        # scan @EXPORT
        if ( !defined *{ $self . '::EXPORT' }{ARRAY} ) {
            *{ $self . '::EXPORT' } = [];
        }
        else {
            my %export = ();

            for my $export ( @{ *{ $self . '::EXPORT' } } ) {
                if ( index( $export, q[:] ) == 0 ) {    # tag found
                    my $tag = substr $export, 1;

                    if ( exists ${ $self . '::EXPORT_TAGS' }{$tag} ) {
                        for my $tag_export ( @{ ${ $self . '::EXPORT_TAGS' }{$tag} } ) {
                            $export{$tag_export} = 1;
                        }
                    }
                    else {
                        die qq[Tag "$export" is not exists in %$self\::EXPORT_TAGS];
                    }
                }
                else {
                    $export{$export} = 1;
                }
            }

            *{ $self . '::EXPORT' } = [ keys %export ];
        }
    }

    # parse tags and pragmas
    my ( $tags, $pragma ) = parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    # do not import to myself
    return if $caller eq $self;

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

    # do not unimport from myself
    return if $caller eq $self;

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
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 87                   │ ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
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
