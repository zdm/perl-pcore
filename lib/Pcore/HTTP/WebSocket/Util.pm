package Pcore::HTTP::WebSocket::Util;

use Pcore;
use Digest::SHA1 qw[];
use Pcore::Util::Data qw[to_b64];

sub get_challenge ( $key ) {
    return to_b64( Digest::SHA1::sha1( ( $key || q[] ) . $WS_GUID ), q[] );
}

# stolen directly from Mojo::WebSocket
sub _build_frame ( $masked, $fin, $rsv1, $rsv2, $rsv3, $op, $data_ref ) {

    # head
    my $head = $op + ( $fin ? 128 : 0 );
    $head |= 0b01000000 if $rsv1;
    $head |= 0b00100000 if $rsv2;
    $head |= 0b00010000 if $rsv3;

    my $frame = pack 'C', $head;

    # small payload
    my $len = length $data_ref->$*;

    if ( $len < 126 ) {
        $frame .= pack 'C', $masked ? ( $len | 128 ) : $len;
    }

    # extended payload (16-bit)
    elsif ( $len < 65536 ) {
        $frame .= pack 'Cn', $masked ? ( 126 | 128 ) : 126, $len;
    }

    # extended payload (64-bit with 32-bit fallback)
    else {
        $frame .= pack 'C', $masked ? ( 127 | 128 ) : 127;

        $frame .= pack( 'Q>', $len );
    }

    # mask payload
    if ($masked) {
        my $mask = pack 'N', int( rand 9 x 7 );

        $data_ref = \( $mask . to_xor( $data_ref->$*, $mask ) );
    }

    return $frame . $data_ref->$*;
}

sub _parse_frame_header ( $buf_ref ) {
    return unless length $buf_ref->$* >= 2;

    my ( $first, $second ) = unpack 'C*', substr( $buf_ref->$*, 0, 2 );

    my $masked = $second & 0b10000000;

    my $res;

    ( my $hlen, $res->{len} ) = ( 2, $second & 0b01111111 );

    # small payload
    if ( $res->{len} < 126 ) {
        $hlen += 4 if $masked;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $header = substr $buf_ref->$*, 0, $hlen, q[];

        $res->{mask} = substr $header, 2, 4, q[] if $masked;
    }

    # extended payload (16-bit)
    elsif ( $res->{len} == 126 ) {
        $hlen = $masked ? 8 : 4;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $header = substr $buf_ref->$*, 0, $hlen, q[];

        $res->{mask} = substr $header, 4, 4, q[] if $masked;

        $res->{len} = unpack 'n', substr $header, 2, 2, q[];
    }

    # extended payload (64-bit with 32-bit fallback)
    elsif ( $res->{len} == 127 ) {
        $hlen = $masked ? 10 : 14;

        return if length $buf_ref->$* < $hlen;

        # cut header
        my $header = substr $buf_ref->$*, 0, 10, q[];

        $res->{mask} = substr $header, 10, 4, q[] if $masked;

        $res->{len} = unpack 'Q>', substr $header, 2, 8, q[];
    }

    # FIN
    $res->{fin} = ( $first & 0b10000000 ) == 0b10000000 ? 1 : 0;

    # RSV1-3
    $res->{rsv1} = ( $first & 0b01000000 ) == 0b01000000 ? 1 : 0;
    $res->{rsv2} = ( $first & 0b00100000 ) == 0b00100000 ? 1 : 0;
    $res->{rsv3} = ( $first & 0b00010000 ) == 0b00010000 ? 1 : 0;

    # opcode
    $res->{op} = $first & 0b00001111;

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 12                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 51                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_parse_frame_header' declared but   |
## |      |                      | not used                                                                                                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 52                   | ControlStructures::ProhibitNegativeExpressionsInUnlessAndUntilConditions - Found ">=" in condition for an      |
## |      |                      | "unless"                                                                                                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 54, 56               | NamingConventions::ProhibitAmbiguousNames - Ambiguously named variable "second"                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 30                   | ValuesAndExpressions::RequireNumberSeparators - Long number not separated with underscores                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 38, 54               | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::WebSocket::Util

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
