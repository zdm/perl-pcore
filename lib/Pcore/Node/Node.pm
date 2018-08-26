package Pcore::Node::Node;

use Pcore -res;
use Pcore::Node;
use Pcore::Util::Data qw[to_cbor];
use if $MSWIN, 'Win32API::File';
use Symbol;

sub run ( $type, $args ) {
    $ENV->scan_deps if $args->{scandeps};

    # ignore SIGINT
    $SIG->{INT} = AE::signal INT => sub { };

    # create object
    my $node = $type->new( $args->{buildargs} // () );

    my $on_event = do {
        if ( $node->can('NODE_ON_EVENT') ) {
            sub ( $h, $ev ) {
                $node->NODE_ON_EVENT($ev);

                return;
            };
        }
    };

    $node->{node} = Pcore::Node->new(
        server   => $args->{server},
        listen   => $args->{listen},
        type     => $type,
        requires => $node->can('NODE_REQUIRES') ? $node->NODE_REQUIRES // undef : undef,
        on_event => $on_event,
        on_rpc   => sub ( $h, $req, $tx ) {
            my $method_name = "API_$tx->{method}";

            if ( my $sub = $node->can($method_name) ) {

                # call method
                eval { $node->$sub( $req, $tx->{args} ? $tx->{args}->@* : () ) };

                $@->sendlog if $@;
            }
            else {
                $req->( [ 400, q[Method not implemented] ] );
            }

            return;
        },
    );

    # open control handle
    my $fh = gensym;

    if ($MSWIN) {
        Win32API::File::OsFHandleOpen( $fh, $args->{fh}, 'rw' ) or die $!;
    }
    else {
        open $fh, '+<&=', $args->{fh} or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
    }

    binmode $fh or die;

    $fh = P->handle($fh);

    my $data = to_cbor { pid => $$ };

    $fh->write( unpack( 'H*', $data->$* ) . $LF );

    # blocks until $fh is closed
    # TODO not working under windows if parent process killed in task manager
    $fh->can_read(undef);

    exit;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 40                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Node::Node

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
