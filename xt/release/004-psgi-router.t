#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;
use Pcore::App;

our $ROUTES = {
    q[/]                   => 'Test::Controller::Index',
    q[/static/]            => 'Test::Controller::Static',
    q[/api/]               => 'Test::Controller::API',
    q[/api/auth/]          => 'Test::Controller::API::Auth',
    q[/api/auth/test/]     => 'Test::Controller::API::Auth::Test',
    q[/api/auth/redirect/] => '/api/auth/test/',
};

our $T = {
    q[/]                         => 'Test::Controller::Index',
    q[/invalid/file.html]        => 'Test::Controller::Index',
    q[/api]                      => 'Test::Controller::Index',
    q[/api/]                     => 'Test::Controller::API',
    q[/api/auth]                 => 'Test::Controller::API',
    q[/api/auth/]                => 'Test::Controller::API::Auth',
    q[/api/auth11/]              => 'Test::Controller::API',
    q[/favicon.ico]              => 'Test::Controller::Index',
    q[/robots.txt]               => 'Test::Controller::Index',
    q[/robots.txt123]            => 'Test::Controller::Index',
    q[/static/images/1.gif]      => 'Test::Controller::Static',
    q[/api/auth/redirect/12.gif] => 'Test::Controller::API::Auth::Test',
};

our $TESTS = keys( %{$T} ) + 2;

if (1) {
    plan skip_all => q[Not ready];
}
else {
    plan tests => $TESTS;
    require_ok('Pcore::PSGI::Router');

    my $r = new_ok( 'Pcore::PSGI::Router' => [ { app => Pcore::App->new( { name => 'test', ns => 'test' } ), appx => undef, _appx_key => 'router' } ] );
    $r->_cache->{routes} = $ROUTES;

    for my $t ( sort keys $T ) {
        ok( $r->path_to_ctrl($t) eq $T->{$t}, $t . ' => ' . $T->{$t} );
    }
}

# say dump $r->_cache;

done_testing $TESTS;

1;
__END__
=pod

=encoding utf8

=cut
