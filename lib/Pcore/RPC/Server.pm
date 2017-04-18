package Pcore::RPC::Server;

use Pcore;
use Pcore::AE::Handle;
use Pcore::HTTP::Server;
use Pcore::WebSocket;
use if $MSWIN, 'Win32API::File';

sub run ( $class, $RPC_BOOT_ARGS ) {

    # ignore SIGINT
    $SIG->{INT} = AE::signal INT => sub {
        return;
    };

    # TODO term on SIGTERM
    $SIG->{TERM} = AE::signal TERM => sub {

        # _on_term();

        return;
    };

    my $cv = AE::cv;

    # create object
    my $rpc = $class->new( $RPC_BOOT_ARGS->{buildargs} // () );

    my $can_rpc_on_connect    = $rpc->can('RPC_ON_CONNECT');
    my $can_rpc_on_disconnect = $rpc->can('RPC_ON_DISCONNECT');

    # parse listen
    my $listen;

    if ( !$RPC_BOOT_ARGS->{listen} ) {

        # for windows use TCP loopback
        if ($MSWIN) {
            $listen = '127.0.0.1:' . P->sys->get_free_port('127.0.0.1');
        }

        # for linux use abstract UDS
        else {
            $listen = "unix:pcore-rpc-$$";
        }
    }
    else {

        # host without port
        if ( $RPC_BOOT_ARGS->{listen} !~ /:/sm ) {
            $listen = "$RPC_BOOT_ARGS->{listen}:" . P->sys->get_free_port( $RPC_BOOT_ARGS->{listen} eq '*' ? () : $RPC_BOOT_ARGS->{listen} );
        }

        # unix socket or fully qualified host:port
        else {
            $listen = $RPC_BOOT_ARGS->{listen};
        }
    }

    # start websocket server
    my $http_server = Pcore::HTTP::Server->new(
        {   listen => $listen,
            app    => sub ($req) {
                Pcore::WebSocket->accept_ws(
                    'pcore', $req,
                    sub ( $ws, $req, $accept, $reject ) {
                        no strict qw[refs];

                        $accept->(
                            {   max_message_size   => 1_024 * 1_024 * 100,     # 100 Mb
                                pong_timeout       => 50,
                                permessage_deflate => 0,
                                on_disconnect      => sub ( $ws, $status ) {
                                    $rpc->RPC_ON_DISCONNECT($ws) if $can_rpc_on_disconnect;

                                    return;
                                },
                                on_rpc_call => sub ( $ws, $req, $method, $args = undef ) {
                                    my $method_name = "API_$method";

                                    if ( $rpc->can($method_name) ) {

                                        # call method
                                        eval { $rpc->$method_name( $req, $args ? $args->@* : () ) };

                                        $@->sendlog if $@;
                                    }
                                    else {
                                        $req->(q[400, q[Method not implemented]]);
                                    }

                                    return;
                                }
                            },
                            headers        => undef,
                            before_connect => {
                                listen_events  => ${"${class}::RPC_LISTEN_EVENTS"},
                                borward_events => ${"${class}::RPC_FORWARD_EVENTS"},
                            },
                            $can_rpc_on_connect ? ( on_connect => sub ($ws) { $rpc->RPC_ON_CONNECT($ws); return } ) : (),
                        );

                        return;
                    },
                );

                return;
            },
        }
    )->run;

    # open control handle
    if ($MSWIN) {
        Win32API::File::OsFHandleOpen( *FH, $RPC_BOOT_ARGS->{ctrl_fh}, 'w' ) or die $!;
    }
    else {
        open *FH, '>&=', $RPC_BOOT_ARGS->{ctrl_fh} or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
    }

    print {*FH} "LISTEN:$listen\x00";

    close *FH or die;

    $cv->recv;

    exit;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 84                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 120                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
