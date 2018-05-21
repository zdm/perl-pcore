package Pcore::Swarm::Const;

use Pcore -export, -const;
use Pcore::Util::UUID qw[uuid_v4_str];

our $EXPORT = [qw[$STATUS_OFFLINE $STATUS_ONLINE]];

const our $STATUS_OFFLINE => 1;
const our $STATUS_ONLINE  => 2;

sub create_listen ($listen) {
    if ( !$listen ) {

        # for windows use TCP loopback
        if ($MSWIN) {
            $listen = '127.0.0.1:' . P->sys->get_free_port('127.0.0.1');
        }

        # for linux use abstract UDS
        else {
            $listen = "unix:\x00pcore-rpc-" . uuid_v4_str;
        }
    }
    else {

        # host without port
        if ( $listen !~ /:/sm ) {
            $listen = "$listen:" . P->sys->get_free_port( $listen eq '*' ? () : $listen );
        }
    }

    return $listen;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 21                   | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Swarm::Const

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
