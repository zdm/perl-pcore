package Pcore::Lib::HTTP;

use Pcore -export, -res;
use Pcore::Lib::Text qw[encode_utf8];
use Pcore::Lib::Scalar qw[is_ref is_plain_arrayref is_plain_scalarref];

our @EXPORT = [qw[compose_headers compose_body compose_body_multipart]];

# https://tools.ietf.org/html/rfc7230#section-3.2
sub compose_headers ( $status, @headers ) {
    $status += 0;

    my $reason = P->result->resolve_reason($status);

    my $buf = "HTTP/1.1 $status $reason\r\n";

    for my $headers (@headers) {
        for ( my $i = 0; $i <= $headers->$#*; $i += 2 ) {
            $buf .= "$headers->[$i]:$headers->[$i + 1]\r\n";
        }
    }

    return \$buf;
}

sub compose_body ( $data ) {
    my $body = $EMPTY;

    for my $part ( $data->@* ) {
        next if !defined $part;

        if ( !is_ref $part ) {
            $body .= encode_utf8 $part;
        }
        elsif ( is_plain_scalarref $part ) {
            $body .= encode_utf8 $part->$*;
        }
        elsif ( is_plain_arrayref $part ) {
            $body .= join $EMPTY, map { encode_utf8 $_ } $part->@*;
        }
        else {
            die q[Body type isn't supported];
        }
    }

    return \$body;
}

sub compose_body_multipart ($data) {
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 18                   | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Lib::HTTP

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
