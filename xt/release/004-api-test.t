#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;
use Pcore::App::API;

our $TESTS = 5;

plan tests => $TESTS;

$Pcore::App::APP_API_ROLES = [ 'admin', 'user' ];

my $app = bless { app_cfg => { api => { connect => 'sqlite:', rpc => { workers => 1 } } } }, 'Pcore::App';

my $api = Pcore::App::API->new($app);

my $res = $api->init;
ok( $res, 'api_init' );

$res = $api->get_user('root');
ok( $res, 'get_user' );

my $sess = $api->create_user_session('root');
ok( $sess, 'create_user_session' );

my $auth;
$api->authenticate( undef, $sess->{data}->{token}, sub { ($auth) = @_ } );
ok( $auth->{is_authenticated}, 'authenticate_session_token_1' );

$api->authenticate( 'root', 'fake_password', sub { ($auth) = @_ } );
ok( !$auth->{is_authenticated}, 'authenticate_password_1' );

done_testing $TESTS;

1;
__END__
=pod

=encoding utf8

=cut