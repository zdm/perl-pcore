#!/usr/bin/env perl

package main v0.1.0;

use Pcore qw[-const];
use Benchmark;
use WWW::Form::UrlEncoded::XS qw[];
use URI::Escape qw[];        ## no critic qw[Modules::ProhibitEvilModules]
use URI::Escape::XS qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Mojo::Util qw[];

const our $COUNT => -5;

# preload
my $uri = P->data->to_uri('мама мыла раму');

say dump $uri;

say P->text->decode( URI::Escape::XS::decodeURIComponent($uri) )->$*;

say P->text->decode( URI::Escape::uri_unescape($uri) )->$*;

say P->data->from_uri($uri);

say Mojo::Util::decode( 'UTF-8', Mojo::Util::url_unescape($uri) );

my $unescape = {
    'URI::Escape::uri_unescape' => sub {
        my $u = URI::Escape::uri_unescape($uri);

        return;
    },
    'URI::Escape::XS::decodeURIComponent' => sub {
        my $u = URI::Escape::XS::decodeURIComponent($uri);

        return;
    },
    'P->data->from_uri' => sub {
        my $u = P->data->from_uri( $uri, encoding => 'UTF-8' );

        return;
    },
    'Mojo::Util::url_unescape' => sub {
        my $u = Mojo::Util::decode( 'UTF-8', Mojo::Util::url_unescape($uri) );

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( $COUNT, $unescape ) );

my $string = 'мама мыла раму = / 123';

say dump URI::Escape::XS::encodeURIComponent($string);

say dump URI::Escape::XS::uri_escape($string);

say dump P->data->to_uri($string);

my $escape = {
    'URI::Escape::uri_escape_utf8' => sub {
        my $u = URI::Escape::uri_escape_utf8($string);

        return;
    },
    'URI::Escape::XS::uri_escape' => sub {
        my $u = URI::Escape::XS::uri_escape($string);

        return;
    },
    'URI::Escape::XS::encodeURIComponent' => sub {
        my $u = URI::Escape::XS::encodeURIComponent($string);

        return;
    },
    'P->data->to_uri' => sub {
        my $u = P->data->to_uri($string);

        return;
    },
    'Mojo::Util::url_unescape' => sub {
        my $u = Mojo::Util::url_escape($string);

        return;
    },
};

Benchmark::cmpthese( Benchmark::timethese( $COUNT, $escape ) );

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
