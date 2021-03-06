#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;
use Pcore::App::API::Auth;
use Pcore::App::API;
use Pcore::Node;

our $TESTS = 4;

plan tests => $TESTS;

package App {

    use Pcore -class;

    with qw[Pcore::App];

    our $PERMS = [ 'admin', 'user' ];

    # PERMISSIONS
    sub get_permissions ($self) {
        return $PERMS;
    }

    sub run { }
}

my $app = bless {
    env => {
        db  => 'sqlite:',
        api => {
            backend      => undef,
            auth_workers => 1,
        }
    },
    node => Pcore::Node->new(
        type     => 'main',
        requires => { 'Pcore::App::API::Node' => undef },
    ),
  },
  'App';

package API {
    use Pcore -class;

    extends qw[Pcore::App::API];
}

my $api = API->new(
    $app->{env}->{api}->%*,
    app => $app,
    db  => $app->{env}->{db},
);

my $res = $api->init;
ok( $res, 'api_init' );

# $res = $api->{backend}->get_user('root');
# ok( $res, 'get_user' );

my $sess = $api->{backend}->user_session_create(1);
ok( $sess, 'user_session_create' );

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
