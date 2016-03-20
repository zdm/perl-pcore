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
my $OBJ = P->class->load( $BOOT_ARGS->{class} )->new( $BOOT_ARGS->{new_args} // () );

# handles are created
our $CV = AE::cv;

my $DEPS    = {};
my $QUEUE   = {};
my $CALL_ID = 0;

# start listen
$IN->on_read(
    sub ($h) {
        $h->unshift_read(
            chunk => 4,
            sub ( $h, $data ) {
                $h->unshift_read(
                    chunk => unpack( 'L>', $data ),
                    sub ( $h, $data ) {
                        _on_data( P->data->from_cbor($data) );

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

sub _on_data ($data) {
    if ( $data->[0]->{method} ) {
        _on_call( $data->[0]->{call_id}, $data->[0]->{method}, $data->[1] );
    }
    else {
        if ( my $cb = delete $QUEUE->{ $data->[0]->{call_id} } ) {
            $cb->( $data->[1] );
        }
    }

    return;
}

sub _on_call_responder ( $call_id, $data ) {

    # make PAR deps snapshot after each call
    my $new_deps;

    if ( $BOOT_ARGS->{scan_deps} ) {
        for my $pkg ( grep { !exists $DEPS->{$_} } keys %INC ) {
            $new_deps = 1;

            $DEPS->{$pkg} = $INC{$pkg};
        }
    }

    my $cbor = P->data->to_cbor(
        [   {   pid     => $$,
                call_id => $call_id,
                deps    => $new_deps ? $DEPS : undef,
            },
            $data
        ]
    );

    $OUT->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

sub _on_call ( $call_id, $method, $data ) {
    if ( !$OBJ->can($method) ) {
        die qq[Unknown RPC method "$method"];
    }
    else {
        my $responder = !defined $call_id ? undef : sub ($data = undef) {
            _on_call_responder( $call_id, $data );

            return;
        };

        $OBJ->$method( $responder, $data );
    }

    return;
}

sub call ( $self, $method, $data = undef, $cb = undef ) {
    my $call_id;

    if ($cb) {
        $call_id = ++$CALL_ID;

        $QUEUE->{$call_id} = $cb;
    }

    # prepare CBOR data
    my $cbor = P->data->to_cbor( [ { pid => $$, call_id => $call_id, method => $method }, $data ] );

    $OUT->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 97                   │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
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
