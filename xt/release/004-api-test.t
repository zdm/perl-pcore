#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;
use Pcore::App::API;

our $TESTS = 5;

plan tests => $TESTS;

package App {

    use Pcore -class;

    with qw[Pcore::App];

    our $API_ROLES = [ 'admin', 'user' ];

    sub run { }

}

my $app = bless { app_cfg => { api => { connect => 'sqlite:', rpc => { workers => 1 } } } }, 'App';

my $api = Pcore::App::API->new($app);

my $res = $api->init;
ok( $res, 'api_init' );

$res = $api->get_user('root');
ok( $res, 'get_user' );

my $sess = $api->create_user_session('root');
ok( $sess, 'create_user_session' );

my $auth;
$auth = $api->authenticate( $sess->{data}->{token} );
ok( $auth->{is_authenticated}, 'authenticate_session_token_1' );

$auth = $api->authenticate( [ 'root', 'fake_password' ] );
ok( !$auth->{is_authenticated}, 'authenticate_password_1' );

done_testing $TESTS;

1;
__END__
=pod

=encoding utf8

=cut
