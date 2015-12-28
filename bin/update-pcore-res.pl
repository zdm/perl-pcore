#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Pcore::Util::URI::Host;

# update TLD
say 'update tld.dat';
Pcore::Util::URI::Host->tlds(1);

# update pub. suffixes, should be updated after TLDs
say 'update pub_suffix.dat';
Pcore::Util::URI::Host->pub_suffixes(1);

# update GeoIP
P->geoip->update_all;

1;
__END__
=pod

=encoding utf8

=cut
