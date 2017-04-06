package Pcore::RPC::Server;

use strict;
use warnings;

our $BOOT_ARGS;

BEGIN {
    require CBOR::XS;

    # shift class name
    my $name = shift @ARGV;

    # read and unpack boot args from STDIN
    $BOOT_ARGS = <>;

    chomp $BOOT_ARGS;

    $BOOT_ARGS = CBOR::XS::decode_cbor( pack 'H*', $BOOT_ARGS );

    # set $main::VERSION
    $main::VERSION = version->new( $BOOT_ARGS->{version} );
}

package    # hide from CPAN
  main;

use Pcore -script_path => $BOOT_ARGS->{script_path}, -result;
use Pcore::AE::Handle;
use if $MSWIN, 'Win32API::File';
use Pcore::Util::UUID qw[uuid_str];
use Pcore::HTTP::Server;
use Pcore::WebSocket;

# open control handle
if ($MSWIN) {
    Win32API::File::OsFHandleOpen( *CTRL_FH, $BOOT_ARGS->{ctrl_fh}, 'w' ) or die $!;
}
else {
    open *CTRL_FH, '>&=', $BOOT_ARGS->{ctrl_fh} or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
}

# ignore SIGINT
$SIG->{INT} = AE::signal INT => sub {
    return;
};

# TODO term on SIGTERM
$SIG->{TERM} = AE::signal TERM => sub {

    # _on_term();

    return;
};

our $CV = AE::cv;

# create object
my $RPC = P->class->load( $BOOT_ARGS->{class} )->new( $BOOT_ARGS->{buildargs} // () );

# get random port on 127.0.0.1 if undef
# TODO do not use port if listen addr. is unix socket
# TODO parse IP addr
my $listen = $BOOT_ARGS->{listen} // '127.0.0.1:' . P->sys->get_free_port('127.0.0.1');

# start websocket server
my $http_server = Pcore::HTTP::Server->new(
    {   listen => $listen,
        app    => sub ($req) {
            Pcore::WebSocket->accept(
                'pcore', $req,
                sub ( $ws, $req, $accept, $decline ) {
                    $accept->(
                        {   max_message_size   => 1_024 * 1_024 * 100,      # 100 Mb
                            pong_timeout       => 50,
                            permessage_deflate => 0,
                            scandeps           => $BOOT_ARGS->{scandeps},
                            on_connect         => sub ($ws) {
                                $RPC->ON_CONNECT($ws) if $RPC->can('ON_CONNECT');

                                return;
                            },
                            on_disconnect => sub ( $ws, $status ) {
                                $RPC->ON_DISCONNECT($ws) if $RPC->can('ON_DISCONNECT');
                            },
                            on_rpc_call => sub ( $req, $method, $args = undef ) {
                                if ( $RPC->can($method) ) {

                                    # call method
                                    eval { $RPC->$method( $req, $args ? $args->@* : () ) };

                                    $@->sendlog if $@;
                                }
                                else {
                                    $req->(q[400, q[Method not implemented]]);
                                }

                                return;
                            }
                        }
                    );

                    return;
                },
            );

            return;
        },
    }
)->run;

# wrap *CTRL_FH
Pcore::AE::Handle->new(
    fh       => \*CTRL_FH,
    on_error => sub ( $h, $fatal, $msg ) {
        die $msg;
    },
    on_connect => sub ( $h, @ ) {

        # handshake
        $h->push_write("LISTEN:$listen\x00");

        # close control connection
        $h->destroy;

        close *CTRL_FH or die;

        return;
    }
);

$CV->recv;

exit;

1;    ## no critic qw[ControlStructures::ProhibitUnreachableCode]
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 90                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 121                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__

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
    if ( $data->{msg} ) {

        # stop receiving messages in TERM state
        return if $TERM;

        if ( $data->{msg} == $RPC_MSG_TERM ) {
            _on_term();
        }
    }

    # RPC method call
    elsif ( $data->{method} ) {

        # stop receiving new calls in TERM state
        return if $TERM;

        _on_method_call( $data->{tid}, $data->{method}, $data->{data} );
    }

    # RPC callback
    else {
        if ( my $cb = delete $QUEUE->{ $data->{tid} } ) {
            $cb->( bless $data, 'Pcore::Util::Result' );
        }
    }

    return;
}

sub _on_method_call ( $tid, $method, $data ) {
    if ( !$RPC->can($method) ) {
        die qq[Unknown RPC method "$method"];
    }
    else {
        my $cb;

        if ( defined $tid ) {
            $cb = sub ($res) {
                $res->{pid}  = $$;
                $res->{tid}  = $tid;
                $res->{deps} = $BOOT_ARGS->[2] ? _get_new_deps() : undef;

                my $cbor = P->data->to_cbor($res);

                $OUT->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

                return;
            };
        }

        my $req = bless { cb => $cb }, 'Pcore::Util::PM::RPC::Request';

        eval { $RPC->$method( $req, $data ? $data->@* : () ) };

        $@->sendlog if $@;
    }

    return;
}

# $method = Str, @data, $cb = Maybe[CodeRef]
sub rpc_call ( $self, $method, @ ) {
    my ( $tid, $cb, $data );

    if ( @_ > 2 ) {
        if ( ref $_[-1] eq 'CODE' ) {
            $cb = $_[-1];

            $data = [ splice @_, 2, -1 ];

            $tid = uuid_str();

            $QUEUE->{$tid} = $cb;
        }
        else {
            $data = [ splice @_, 2 ];
        }
    }

    # prepare CBOR data
    my $cbor = P->data->to_cbor(
        {   pid    => $$,
            tid    => $tid,
            method => $method,
            deps   => $BOOT_ARGS->[2] ? _get_new_deps() : undef,
            data   => $data,
        }
    );

    $OUT->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

    return;
}

1;    ## no critic qw[ControlStructures::ProhibitUnreachableCode]
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::RPC::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
