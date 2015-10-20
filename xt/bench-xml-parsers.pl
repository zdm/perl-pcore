#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Const::Fast;
use Benchmark qw[];

const our $COUNT => -5;

my $XML = <<'XML';
<?xml version="1.0"?>
<!--
  FoxyProxy
  Copyright (C) 2006-2015 Eric H. Jung and FoxyProxy, Inc.
  http://getfoxyproxy.org/
  eric.jung@getfoxyproxy.org

  This source code is released under the GPL license,
  available in the LICENSE file at the root of this installation
  and also online at http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
-->
<RDF xmlns="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    xmlns:em="http://www.mozilla.org/2004/em-rdf#"
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">

    <Description rdf:about="urn:mozilla:install-manifest">
        <em:unpack>true</em:unpack>
<!-- begin-foxyproxy-standard -->
        <em:id>foxyproxy@eric.h.jung</em:id>
        <em:name>FoxyProxy Standard</em:name>
        <em:version>4.5.3</em:version>
<!-- end-foxyproxy-standard -->
<!-- begin-foxyproxy-simple
        <em:id>foxyproxy-basic@eric.h.jung</em:id>
        <em:name>FoxyProxy Basic</em:name>
        <em:version>3.5.3</em:version>
end-foxyproxy-simple -->

        <em:creator>FoxyProxy, Inc.</em:creator>
        <em:description>Premier proxy management for Firefox</em:description>
        <em:homepageURL>http://getfoxyproxy.org</em:homepageURL>
        <em:aboutURL>chrome://foxyproxy/content/about.xul</em:aboutURL>
        <em:optionsURL>chrome://foxyproxy/content/options.xul</em:optionsURL>
        <em:iconURL>chrome://foxyproxy/content/images/foxyproxy-nocopy.gif</em:iconURL>
        <!-- Firefox -->
        <em:targetApplication>
            <Description>
                <em:id>{ec8030f7-c20a-464f-9b0e-13a3a9e97384}</em:id>
                <em:minVersion>3.1b3</em:minVersion>
                <em:maxVersion>39.0</em:maxVersion>
            </Description>
        </em:targetApplication>
        <!-- SeaMonkey -->
        <em:targetApplication>
         <Description>
            <em:id>{92650c4d-4b8e-4d2a-b7eb-24ecf4f6b63a}</em:id>
            <em:minVersion>2.0a</em:minVersion>
            <em:maxVersion>2.36</em:maxVersion>
          </Description>
        </em:targetApplication>
        <!-- Thunderbird -->
        <em:targetApplication>
            <Description>
                <em:id>{3550f703-e582-4d05-9a08-453d09bdfdc6}</em:id>
                <em:minVersion>3.0a1pre</em:minVersion>
                <em:maxVersion>39.0</em:maxVersion>
            </Description>
        </em:targetApplication>
        <!-- Palemoon -->
        <em:targetApplication>
            <Description>
                <em:id>{8de7fcbb-c55c-4fbe-bfc5-fc555c87dbc4}</em:id>
                <em:minVersion>25.0</em:minVersion>
                <em:maxVersion>25.*</em:maxVersion>
            </Description>
        </em:targetApplication>
    </Description>
</RDF>
XML

require XML::Hash::XS;
require XML::Bare;
require XML::Fast;

my $xml_hash_xs = XML::Hash::XS->new;

my $tests = {
    'Pcore::Data::from_xml' => sub {
        P->data->decode( \$XML, from => 'XML' );

        return;
    },
    'XML::Hash::XS' => sub {
        $xml_hash_xs->xml2hash( \$XML );

        return;
    },
    'XML::Bare' => sub {
        XML::Bare->new( text => $XML )->parse;

        return;
    },
    'XML::Fast' => sub {
        XML::Fast::xml2hash($XML);

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( $COUNT, $tests ) );

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
