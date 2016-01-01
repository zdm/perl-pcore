#!/usr/bin/env perl

package main v0.1.0;

use Pcore -const;
use Benchmark qw[];
use Storable qw[];
use Data::Dumper qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use JSON::XS qw[];        ## no critic qw[Modules::ProhibitEvilModules]
use Data::MessagePack qw[];
use CBOR::XS qw[];

const our $COUNT => -5;

our $TEST_DATA = {
    '203.174.65.12'   => 'JP',
    '212.208.74.140'  => 'FR',
    '200.219.192.106' => 'BR',
    '134.102.101.18'  => 'DE',
    '193.75.148.28'   => 'BE',
    '147.251.48.1'    => 'CZ',
    '194.244.83.2'    => 'IT',
    '203.15.106.23'   => 'AU',
    '196.31.1.1'      => 'ZA',
    '210.54.22.1'     => 'NZ',
    '210.25.5.5'      => 'CN',
    '210.54.122.1'    => 'NZ',
    '210.25.15.5'     => 'CN',
    '192.37.51.100'   => 'CH',
    '192.37.150.150'  => 'CH',
    '192.106.51.100'  => 'IT',
    '192.106.150.150' => 'IT',
};

my $hash = $TEST_DATA;

for ( 1 .. 100 ) {
    my $key = rand 9999;

    $hash->{$key} = Storable::dclone($hash);

    $hash = $hash->{$key};
}

$Data::Dumper::Indent    = 0;
$Data::Dumper::Quotekeys = 0;
$Data::Dumper::Useqq     = 0;
$Data::Dumper::Pair      = q[=>];

my %json_args = (
    ascii           => 1,
    latin1          => 0,
    utf8            => 1,
    pretty          => 0,    # set indent, space_before, space_after
    canonical       => 0,    # sort hash keys, slow
    allow_nonref    => 1,    # allow scalars
    allow_unknown   => 0,    # trow exception if can't encode item
    allow_blessed   => 1,    # allow blessed objects
    convert_blessed => 1,    # use TO_JSON method of blessed objects
    allow_tags      => 0,    # use FREEZE / THAW
);

my $json_precached = JSON::XS->new;

for ( keys %json_args ) {
    $json_precached->$_( $json_args{$_} );
}

my $tests = {
    's JSON'       => \&seralizer_json_raw_precached,
    's JSON b64'   => \&seralizer_json_b64_precached,
    's JSON zip'   => \&seralizer_json_compressed_precached,
    's Dumper'     => \&serializer_data_dumper_raw,
    's Dumper zip' => \&serializer_data_dumper_compressed,
    'JSON'         => \&json_raw,
    'JSON cache'   => \&json_raw_precached,
    'Dumper'       => \&data_dumper_raw,
    'MessagePack'  => \&data_messagepack_raw,
    'CBOR'         => \&data_cbor_raw,
};

# measure packed data size
my $packed = {};

for my $test ( keys $tests ) {
    $packed->{$test} = bytes::length $tests->{$test}->();
}

for my $test ( sort { $packed->{$a} <=> $packed->{$b} } keys $packed ) {
    say sprintf q[%-15s - %u], $test, $packed->{$test};
}

Benchmark::cmpthese( Benchmark::timethese( $COUNT, $tests ) );

sub seralizer_json_raw_precached {
    return P->data->to_json($TEST_DATA)->$*;
}

sub seralizer_json_b64_precached {
    return P->data->to_json( $TEST_DATA, encode => 1 )->$*;
}

sub seralizer_json_compressed_precached {
    return P->data->to_json( $TEST_DATA, compress => 1 )->$*;
}

sub serializer_data_dumper_raw {
    return P->data->to_perl($TEST_DATA)->$*;
}

sub serializer_data_dumper_compressed {
    return P->data->to_perl( $TEST_DATA, compress => 1 )->$*;
}

sub json_raw {
    my $json = JSON::XS->new;
    for ( keys %json_args ) {
        $json->$_( $json_args{$_} );
    }

    return $json->encode($TEST_DATA);
}

sub json_raw_precached {
    return $json_precached->encode($TEST_DATA);
}

sub data_dumper_raw {
    return Data::Dumper->Dump( [$TEST_DATA] );
}

sub storable_raw {
    return Storable::store( [$TEST_DATA] );
}

sub data_messagepack_raw {
    my $mp = Data::MessagePack->new;

    return $mp->pack( [$TEST_DATA] );
}

sub data_cbor_raw {
    my $cbor = CBOR::XS->new;

    return $cbor->encode( [$TEST_DATA] );
}

1;
__END__
=pod

=encoding utf8

=cut
