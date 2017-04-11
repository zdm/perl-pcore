package Pcore::RPC::Server;

use Pcore;
use Pcore::AE::Handle;
use Pcore::HTTP::Server;
use Pcore::WebSocket;
use if $MSWIN, 'Win32API::File';

sub run ( $class, $RPC_BOOT_ARGS ) {

    # open control handle
    if ($MSWIN) {
        Win32API::File::OsFHandleOpen( *CTRL_FH, $RPC_BOOT_ARGS->{ctrl_fh}, 'w' ) or die $!;
    }
    else {
        open *CTRL_FH, '>&=', $RPC_BOOT_ARGS->{ctrl_fh} or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
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

    my $cv = AE::cv;

    # create object
    my $rpc = $class->new( $RPC_BOOT_ARGS->{buildargs} // () );

    my $can_rpc_before_connect = $rpc->can('RPC_BEFORE_CONNECT');
    my $can_rpc_on_connect     = $rpc->can('RPC_ON_CONNECT');
    my $can_rpc_on_disconnect  = $rpc->can('RPC_ON_DISCONNECT');

    # get random port on 127.0.0.1 if undef
    # TODO do not use port if listen addr. is unix socket
    # TODO parse IP addr
    my $listen = $RPC_BOOT_ARGS->{listen} // '127.0.0.1:' . P->sys->get_free_port('127.0.0.1');

    # start websocket server
    my $http_server = Pcore::HTTP::Server->new(
        {   listen => $listen,
            app    => sub ($req) {
                Pcore::WebSocket->accept_ws(
                    'pcore', $req,
                    sub ( $ws, $req, $accept, $reject ) {
                        $accept->(
                            {   max_message_size   => 1_024 * 1_024 * 100,     # 100 Mb
                                pong_timeout       => 50,
                                permessage_deflate => 0,
                                on_disconnect      => sub ( $ws, $status ) {
                                    $rpc->RPC_ON_DISCONNECT($ws) if $can_rpc_on_disconnect;

                                    return;
                                },
                                on_rpc_call => sub ( $ws, $req, $method, $args = undef ) {
                                    if ( $rpc->can($method) ) {

                                        # call method
                                        eval { $rpc->$method( $req, $args ? $args->@* : () ) };

                                        $@->sendlog if $@;
                                    }
                                    else {
                                        $req->(q[400, q[Method not implemented]]);
                                    }

                                    return;
                                }
                            },
                            headers => undef,
                            $can_rpc_before_connect ? ( before_connect => $rpc->RPC_BEFORE_CONNECT ) : (),
                            $can_rpc_on_connect ? ( on_connect => sub ($ws) { $rpc->RPC_ON_CONNECT($ws); return } ) : (),
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
## |    3 | 66                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 100                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
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
