package Pcore::Util::PM::RPC::Server;

use strict;
use warnings;

our $BOOT_ARGS;

# TODO do not use $0 and FindBin
BEGIN {

    # preload Filter::Crypto::Decrypt to avoid "Can't run with Perl compiler backend" fatal error under crypted PAR
    require Filter::Crypto::Decrypt;
    require CBOR::XS;

    # shift class name
    my $name = shift @ARGV;

    # read and unpack boot args from STDIN
    $BOOT_ARGS = <>;

    chomp $BOOT_ARGS;

    $BOOT_ARGS = CBOR::XS::decode_cbor( pack 'H*', $BOOT_ARGS );

    $0 = "$BOOT_ARGS->[0] $name";    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    $main::VERSION = version->new( $BOOT_ARGS->[1] );
}

package                              # hide from CPAN
  main;

use Pcore;
use Pcore::AE::Handle;
use if $MSWIN, 'Win32API::File';
use Pcore::Util::PM::RPC qw[:CONST];
use Pcore::Util::UUID qw[uuid_str];

if ($MSWIN) {
    Win32API::File::OsFHandleOpen( *IN,  $BOOT_ARGS->[3], 'r' ) or die $!;
    Win32API::File::OsFHandleOpen( *OUT, $BOOT_ARGS->[4], 'w' ) or die $!;
}
else {
    open *IN,  '<&=', $BOOT_ARGS->[3] or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
    open *OUT, '>&=', $BOOT_ARGS->[4] or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
}

my $IN;                                             # read from
my $OUT;                                            # write to

# wrap IN
Pcore::AE::Handle->new(
    fh       => \*IN,
    on_error => sub ( $h, $fatal, $msg ) {
        _on_term();

        return;
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
        _on_term();

        return;
    },
    on_connect => sub ( $h, @ ) {
        $OUT = $h;

        return;
    }
);

# ignore INT
$SIG->{INT} = AE::signal INT => sub {
    return;
};

# term on TERM
$SIG->{TERM} = AE::signal TERM => sub {
    _on_term();

    return;
};

my $RPC;
my $DEPS  = {};
my $QUEUE = {};
my $TERM;

our $CV = AE::cv;

# handshake, send PID
$OUT->push_write("READY1$$\x00");

$IN->unshift_read(
    chunk => 4,
    sub ( $h, $len ) {
        $h->unshift_read(
            chunk => unpack( 'L>', $len ),
            sub ( $h, $data ) {
                my $init = P->data->from_cbor($data);

                $OUT->push_write("READY2$$\x00");

                # create object
                $RPC = P->class->load( $init->{class} )->new( $init->{buildargs} // () );

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

                return;
            }
        );

        return;
    }
);

$CV->recv;

exit;

sub _get_new_deps {
    my $new_deps;

    if ( $BOOT_ARGS->[2] ) {
        for my $pkg ( grep { !exists $DEPS->{$_} } keys %INC ) {
            $DEPS->{$pkg} = undef;

            push $new_deps->@*, $pkg;
        }
    }

    return $new_deps;
}

sub _on_term {
    return if $TERM;

    $TERM = 1;

    $RPC->RPC_ON_TERM if $RPC->can('RPC_ON_TERM');

    return;
}

sub _on_data ($data) {
    if ( $data->[0]->{msg} ) {

        # stop receiving messages in TERM state
        return if $TERM;

        if ( $data->[0]->{msg} == $RPC_MSG_TERM ) {
            _on_term();
        }
    }
    elsif ( $data->[0]->{method} ) {

        # stop receiving new calls in TERM state
        return if $TERM;

        _on_call( $data->[0]->{call_id}, $data->[0]->{method}, $data->[1] );
    }
    else {
        if ( my $cb = delete $QUEUE->{ $data->[0]->{call_id} } ) {
            $cb->( $data->[1] ? $data->[1]->@* : () );
        }
    }

    return;
}

sub _on_call_responder ( $cid, $data ) {
    my $cbor = P->data->to_cbor(
        [   {   pid     => $$,
                call_id => $cid,
                deps    => $BOOT_ARGS->[2] ? _get_new_deps() : undef,
            },
            $data
        ]
    );

    $OUT->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

sub _on_call ( $cid, $method, $args ) {
    if ( !$RPC->can($method) ) {
        die qq[Unknown RPC method "$method"];
    }
    else {
        my $cb = !defined $cid ? undef : sub (@) {
            _on_call_responder( $cid, @_ ? \@_ : undef );

            return;
        };

        $RPC->$method( $cb, $args ? $args->@* : () );
    }

    return;
}

# $method = Str, @args, $cb = Maybe[CodeRef]
sub rpc_call ( $self, $method, @ ) {
    my ( $cid, $cb, $args );

    if ( @_ > 2 ) {
        if ( ref $_[-1] eq 'CODE' ) {
            $cb = $_[-1];

            $args = [ splice @_, 2, -1 ];

            $cid = uuid_str();

            $QUEUE->{$cid} = $cb;
        }
        else {
            $args = [ splice @_, 2 ];
        }
    }

    # prepare CBOR data
    my $cbor = P->data->to_cbor(
        [   {   pid     => $$,
                call_id => $cid,
                deps    => $BOOT_ARGS->[2] ? _get_new_deps() : undef,
                method  => $method,
            },
            $args
        ]
    );

    $OUT->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

1;    ## no critic qw[ControlStructures::ProhibitUnreachableCode]
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 101, 111             | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
