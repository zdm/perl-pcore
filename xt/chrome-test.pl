#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Pcore::API::Chrome;

my $chrome = Pcore::API::Chrome->new( bin => $MSWIN ? 'vivaldi' : undef );

my $tab = $chrome->new_tab('https://www.google.com');

Coro::sleep 3;

say dump $tab->get_cookies;

1;
__END__
=pod

=encoding utf8

=cut
