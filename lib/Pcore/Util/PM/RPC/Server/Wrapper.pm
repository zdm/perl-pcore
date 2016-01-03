package Pcore::Util::PM::RPC::Server::Wrapper;

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

my $cv = AE::cv;

my ( $in, $out );

$cv->begin;

Pcore::AE::Handle->new(
    fh         => \*IN,
    on_connect => sub ( $h, @ ) {
        $in = $h;

        $cv->end;

        return;
    }
);

$cv->begin;

Pcore::AE::Handle->new(
    fh         => \*OUT,
    on_connect => sub ( $h, @ ) {
        $out = $h;

        $cv->end;

        return;
    }
);

$cv->recv;

# handles are created
$cv = AE::cv;

my $obj = P->class->load( $BOOT_ARGS->{class} )->new( $BOOT_ARGS->{args} );

my $deps = {};

# start listener
my $listener = sub ($req) {
    my $call_id = $req->[0];

    my $method = $req->[1];

    $obj->$method(
        sub ($res = undef) {

            # make PAR deps snapshot after each call
            my $new_deps;

            if ( $BOOT_ARGS->{scan_deps} ) {
                for my $pkg ( grep { !exists $deps->{$_} } keys %INC ) {
                    $new_deps = 1;

                    $deps->{$pkg} = $INC{$pkg};
                }
            }

            my $data = P->data->to_cbor( [ $new_deps ? $deps : undef, $call_id, $res ] );

            $out->push_write( pack( 'L>', bytes::length $data->$* ) . $data->$* );

            return;
        },
        $req->[2],
    );

    return;
};

$in->on_read(
    sub ($h) {
        $h->unshift_read(
            chunk => 4,
            sub ( $h, $data ) {
                my $len = unpack 'L>', $data;

                $h->unshift_read(
                    chunk => $len,
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
$out->push_write("READY$$\x00");

$cv->recv;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 130                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC::Server::Wrapper

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
