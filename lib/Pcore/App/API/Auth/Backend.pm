package Pcore::App::API::Auth::Backend;

use Pcore -role;

requires(
    'init',

    # app
    'register_app_instance',
    'approve_app_instance',
    'connect_app_instance',

    # user
    'get_user_by_id',
    'get_user_by_name',
    'create_user',
    'set_user_password',
    'set_user_enabled',
    'set_user_role',
    'create_user_token',

    # role
    'create_role',
    'set_role_enabled',
    'set_role_methods',
    'add_role_methods',

    # token
    'set_token_enabled',
    'delete_token',
);

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Backend

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
