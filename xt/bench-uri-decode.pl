#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Const::Fast;
use Benchmark;
use WWW::Form::UrlEncoded::XS qw[];
use URI::Escape qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Mojo::Util qw[];

Const::Fast::const our $COUNT => -5;

# preload
my $uri = P->data->to_uri('мама мыла раму');

say dump $uri;

say P->text->decode( URI::Escape::XS::decodeURIComponent($uri) )->$*;

say P->text->decode( URI::Escape::uri_unescape($uri) )->$*;

say P->data->from_uri($uri);

say Mojo::Util::decode( 'UTF-8', Mojo::Util::url_unescape($uri) );

my $tests = {
    uri_escape => sub {
        my $u = URI::Escape::uri_unescape($uri);

        return;
    },
    uri_escape_xs => sub {
        my $u = URI::Escape::XS::decodeURIComponent($uri);

        return;
    },
    p_data_from_uri => sub {
        my $u = P->data->from_uri( $uri, encoding => 'UTF-8' );

        return;
    },
    mojo => sub {
        my $u = Mojo::Util::decode( 'UTF-8', Mojo::Util::url_unescape($uri) );

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
