package Pcore::Util::Net;

use Pcore;
use Pcore::Util::UUID qw[uuid_v4_str];

sub resolve_listen ($listen) {
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
## |    2 | 16                   | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Net

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
