package Pcore::Core::Exporter;

use Pcore;
use if $^V ge 'v5.10', feature  => ':all';
no  if $^V ge 'v5.18', warnings => 'experimental';

our $CACHE;

no Pcore;

sub import {
    my $self = shift;

    # parse tags and pragmas
    my ( $tag, $pragma, $data ) = parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    # export import, unimport methods
    {
        no strict qw[refs];

        *{ $caller . '::import' } = \&_import;

        *{ $caller . '::unimport' } = \&_unimport;
    }

    return;
}

sub parse_import {
    my $caller = shift;

    my ( $tag, $pragma, $data );

    my $export_pragma = do {
        no strict qw[refs];

        ${ $caller . '::EXPORT_PRAGMA' };
    };

    while ( my $arg = shift ) {
        if ( ref $arg eq 'HASH' ) {
            $data = $arg;
        }
        elsif ( substr( $arg, 0, 1 ) eq q[-] ) {
            substr $arg, 0, 1, q[];

            if ( $arg eq 'level' || $arg eq 'caller' ) {
                $pragma->{$arg} = shift;
            }
            elsif ( $export_pragma && exists $export_pragma->{$arg} ) {
                $pragma->{$arg} = $export_pragma->{$arg} ? shift : 1;
            }
            else {
                die qq[Unknown exporter pragma found "-$arg" while importing package "$caller"];
            }

        }
        else {
            push $tag->@*, $arg;
        }
    }

    return $tag, $pragma, $data;
}

sub _import {
    my $self = shift;

    # parse tags and pragmas
    my ( $tag, $pragma, $data ) = parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    # protection from re-exporting to myself
    return if $caller eq $self;

    _export_tags( $self, $caller, $tag );

    return;
}

# TODO process unimport tags
sub _unimport {
    my $self = shift;

    # parse tags and pragmas
    my ( $tag, $pragma, $data ) = parse_import( $self, @_ );

    # find caller
    my $caller = $pragma->{caller} // caller( $pragma->{level} // 0 );

    # protection from re-exporting to myself
    return if $caller eq $self;

    if ( exists $CACHE->{$self} && exists $CACHE->{$self}->{DEFAULT} ) {
        my $cache = $CACHE->{$self}->{ALL};

        no strict qw[refs];

        # unimport all symbols, declared in :DEFAULT tag
        # NOTE only subroutines can be unimported right now
        for my $sym ( keys $CACHE->{$self}->{DEFAULT}->%* ) {
            if ( $cache->{$sym}->[1] eq q[] ) {
                delete ${ $caller . q[::] }{ $cache->{$sym}->[0] };
            }
        }
    }

    return;
}

sub _export_tags ( $self, $caller, $tag ) {

    # cache exporter configuration
    if ( !exists $CACHE->{$self} ) {
        my $export_tag = do {
            no strict qw[refs];

            ${ $self . '::EXPORT' };
        };

        if ( !$export_tag ) {
            $CACHE->{$self} = undef;
        }
        else {
            my $cache;

            $export_tag = { ALL => $export_tag } if ref $export_tag eq 'ARRAY';

            my $tags;    # 0 - processing, 1 - done

            my $process_tag = sub ($tag) {

                # tag is already processed
                return if $tags->{$tag};

                die qq[Cyclic reference found whils processing export tag "$tag"] if exists $tags->{$tag} && !$tags->{$tag};

                $tags->{$tag} = 0;

                for ( $export_tag->{$tag}->@* ) {
                    my $sym = $_;

                    my $type = $sym =~ s/\A([:&\$@%*])//sm ? $1 : q[];

                    if ( $type ne q[:] ) {
                        $type = q[] if $type eq q[&];

                        $cache->{$tag}->{ $type . $sym } = 1;

                        $cache->{ALL}->{ $type . $sym } = [ $sym, $type ];
                    }
                    else {
                        die qq["ALL" export tag can not contain references to the other tags in package "$self"] if $tag eq 'ALL';

                        __SUB__->($sym);

                        $cache->{$tag}->@{ keys $cache->{$sym}->%* } = values $cache->{$sym}->%*;
                    }
                }

                # mark tag as processed
                $tags->{$tag} = 1;

                return;
            };

            for my $tag ( keys $export_tag->%* ) {
                die qq["ALL" tag name is reserved in package "$self"] if $tag eq ':ALL';

                $process_tag->($tag);
            }

            $CACHE->{$self} = $cache;
        }
    }

    my $export = $CACHE->{$self};

    if ( !$tag ) {
        if ( !$export ) {
            return;
        }
        elsif ( !exists $export->{DEFAULT} ) {
            return;
        }
        else {
            push $tag->@*, ':DEFAULT';
        }
    }
    else {
        die qq[Package "$self" doesn't export anything] if !$export;
    }

    # gather symbols to export
    my $symbols;

    for my $sym ( $tag->@* ) {
        my $no_export;

        my $is_tag;

        if ( $sym =~ s/\A([!:])//sm ) {
            if ( $1 eq q[!] ) {
                $no_export = 1;

                $is_tag = 1 if $sym =~ s/\A://sm;
            }
            else {
                $is_tag = 1;
            }
        }

        if ($is_tag) {
            die qq[Unknown tag ":$sym" to import from "$self"] if !exists $export->{$sym};

            if ($no_export) {
                delete $symbols->@{ keys $export->{$sym}->%* };
            }
            else {
                $symbols->@{ keys $export->{$sym}->%* } = values $export->{$sym}->%*;
            }
        }
        else {
            $sym =~ s/\A&//sm;

            die qq[Unknown symbol "$sym" to import from package "$self"] if !exists $export->{ALL}->{$sym};

            if ($no_export) {
                delete $symbols->{$sym};
            }
            else {
                $symbols->{$sym} = 1;
            }
        }
    }

    # export
    if ( $symbols->%* ) {
        for my $sym ( keys $symbols->%* ) {
            my $type = $export->{ALL}->{$sym}->[1];

            {
                no strict qw[refs];

                no warnings qw[once];

                *{"$caller\::$export->{ALL}->{$sym}->[0]"}
                  = $type eq q[]  ? \&{"$self\::$export->{ALL}->{$sym}->[0]"}
                  : $type eq q[$] ? \${"$self\::$export->{ALL}->{$sym}->[0]"}
                  : $type eq q[@] ? \@{"$self\::$export->{ALL}->{$sym}->[0]"}
                  : $type eq q[%] ? \%{"$self\::$export->{ALL}->{$sym}->[0]"}
                  : $type eq q[*] ? *{"$self\::$export->{ALL}->{$sym}->[0]"}
                  :                 die;
            }
        }
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 106, 162, 172, 222,  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 225, 243, 244        │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 116                  │ Subroutines::ProhibitExcessComplexity - Subroutine "_export_tags" with high complexity score (42)              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Exporter

=head1 SYNOPSIS

    use Pcore::Core::Exporter;

    our $EXPORT = [ ...SYMBOLS TO EXPORT... ];

        or

    our $EXPORT = {
        TAG1    => [qw[sub1 $var1 ... ]],
        TAG2    => [qw[:TAG1 sub2 $var2 ... ]],
        DEFAULT => [qw[:TAG1 :TAG2 sym3 ...]],
    };

    our $EXPORT_PRAGMA = {
        trigger => 0,
        option  => 1,
    };

    ...

    use Package qw[-trigger -option OPTION_VALUE :TAG1 !:TAG2 sub1 !sub2 $var1 !$var2 @arr1 !@arr2 %hash1 !%hash2 *sym1 !*sym2], {};

=head1 DESCRIPTION

Tag ":ALL" is reserver and is created automatically.

If no symbols / tags are specified for import - ":DEFAULT" tag will be exported, if defined.

=head1 SEE ALSO

=cut
