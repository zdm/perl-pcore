package Pcore::App::API::Backend;

use Pcore -role;

requires(
    '_build_host',
    'init',

    # AUTH
    'auth_user_password',

    # APP
    'get_app_by_id',
    'create_app',
    'set_app_enabled',
    'delete_app',

    # APP INSTANCE
    'get_app_instance_by_id',
    'create_app_instance',
    'approve_app_instance',
    'set_app_instance_enabled',
    'delete_app_instance',

    # ROLE
    'get_role_by_id',
    'create_role',
    'set_role_enabled',

    # USER
    'get_user_by_id',
    'get_user_by_name',
    'create_user',
    'set_user_password',
    'set_user_enabled',
    'set_user_role',

    # USER TOKEN
    'create_user_token',
    'delete_user_token',
);

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has host => ( is => 'lazy', isa => Str, init_arg => undef );                         # backend host name
has is_connected => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # backend is connected

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
