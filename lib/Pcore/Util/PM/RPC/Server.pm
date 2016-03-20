package Pcore::Util::PM::RPC::Server;

use strict;
use warnings;

our $BOOT_ARGS;

BEGIN {
    require CBOR::XS;

    $BOOT_ARGS = CBOR::XS::decode_cbor( pack 'H*', shift @ARGV );

    $0 = $BOOT_ARGS->{script}->{path};    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    $main::VERSION = version->new( $BOOT_ARGS->{script}->{version} );
}

package                                   # hide from CPAN
  main;

use Pcore;
use Pcore::AE::Handle;
use if $MSWIN, 'Win32API::File';

if ($MSWIN) {
    Win32API::File::OsFHandleOpen( *IN,  $BOOT_ARGS->{ipc}->{in},  'r' ) or die $!;
    Win32API::File::OsFHandleOpen( *OUT, $BOOT_ARGS->{ipc}->{out}, 'w' ) or die $!;
}
else {
    open *IN,  '<&=', $BOOT_ARGS->{ipc}->{in}  or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
    open *OUT, '>&=', $BOOT_ARGS->{ipc}->{out} or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
}

my $IN;                                                      # read from
my $OUT;                                                     # write to

# wrap IN
Pcore::AE::Handle->new(
    fh       => \*IN,
    on_error => sub ( $h, $fatal, $msg ) {
        exit;
    },
    on_connect => sub ( $h, @ ) {
        $IN = $h;

        return;
    }
);

# wrap OUT
Pcore::AE::Handle->new(
    fh       => \*OUT,
    on_error => sub ( $h, $fatal, $msg ) {
        exit;
    },
    on_connect => sub ( $h, @ ) {
        $OUT = $h;

        return;
    }
);

# create object
my $obj = P->class->load( $BOOT_ARGS->{class} )->new( $BOOT_ARGS->{new_args} // () );

# handles are created
our $CV = AE::cv;

my $deps = {};

# create listener
my $listener = sub ($req) {
    my $call_id = $req->[0];

    my $method = $req->[1];

    my $responder = sub ( $call_id, $res ) {

        # make PAR deps snapshot after each call
        my $new_deps;

        if ( $BOOT_ARGS->{scan_deps} ) {
            for my $pkg ( grep { !exists $deps->{$_} } keys %INC ) {
                $new_deps = 1;

                $deps->{$pkg} = $INC{$pkg};
            }
        }

        my $data = P->data->to_cbor( [ [ $new_deps ? $deps : undef, $call_id, $$ ], $res ] );

        $OUT->push_write( pack( 'L>', bytes::length $data->$* ) . $data->$* );

        return;
    };

    if ( !$obj->can($method) ) {
        $responder->( $call_id, undef );
    }
    else {
        $obj->$method(
            sub ($data = undef) {
                $responder->( $call_id, $data );

                return;
            },
            $req->[2],
        );
    }

    return;
};

# start listen
$IN->on_read(
    sub ($h) {
        $h->unshift_read(
            chunk => 4,
            sub ( $h, $data ) {
                $h->unshift_read(
                    chunk => unpack( 'L>', $data ),
                    sub ( $h, $data ) {
                        $listener->( P->data->from_cbor($data) );

                        return;
                    }
                );

                return;
            }
        );

        return;
    }
);

# handshake, send PID
$OUT->push_write("READY$$\x00");

$CV->recv;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 138                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
