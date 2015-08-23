#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use AnyEvent::Handle qw[];
use AnyEvent::Socket qw[];

my $guard = AnyEvent::Socket::tcp_server( 0, 8080, \&accept_req );

sub accept_req ( $fh, $host, $port ) {
    my $h = AnyEvent::Handle->new( fh => $fh );

    $h->push_write(qq[HTTP/1.1 200 OK${CRLF}Transfer-Encoding: chunked${CRLF}${CRLF}]);

    $h->push_write(qq[6${CRLF}chunk1${CRLF}]);

    $h->push_write(qq[6${CRLF}chunk2${CRLF}]);

    $h->push_write(qq[0${CRLF}T-Header: 1${CRLF}T-Header: 2${CRLF}${CRLF}]);

    return;
}

P->cv->recv;

1;
__END__
=pod

=encoding utf8

=head1 REQUIRED ARGUMENTS

=over

=back

=head1 OPTIONS

=over

=back

=cut
