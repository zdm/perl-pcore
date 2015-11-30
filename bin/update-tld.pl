#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Pcore::Util::URI::Host;

my $cv = AE::cv;

Pcore::Util::URI::Host::tlds($cv);

$cv->recv;

1;
__END__
=pod

=encoding utf8

=cut
