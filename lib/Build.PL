#!/usr/bin/env perl

package main v0.1.0;

use FindBin;
use lib "$FindBin::RealBin/lib";

use Pcore;
use Pcore::Util::URI::Host;

sub CLI {
    return { arg => [ script => { isa => 'Str' } ] };
}

Pcore::Util::URI::Host->update_all or exit 3;

1;
__END__
=pod

=encoding utf8

=cut
