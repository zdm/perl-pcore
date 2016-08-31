package Pcore::App::API::Auth;

use Pcore -role;
use Pcore::Util::Status;

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

has user_cache        => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has username_id_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

around init => sub ( $orig, $self, $cb ) {

    # init auth backend, create DB schema
    $self->$orig(
        sub ($status) {
            die qq[Error initialising API auth backend: $status] if !$status;

            my ( $app_instance_id, $app_instance_token );

            my $app_instance_file = ( $ENV->{DATA_DIR} // q[] ) . '.app-instance.txt';

            if ( !-f $app_instance_file ) {
                P->file->touch($app_instance_file);
            }
            else {
                my $data = P->file->read_bin($app_instance_file);

                ( $app_instance_id, $app_instance_token ) = split /:/sm, $data->$*;
            }

            my $connect_app_instance = sub ( $app_instance_id, $app_instance_token ) {
                $self->connect_app_instance(
                    $app_instance_id,
                    $app_instance_token,
                    sub ($status) {
                        die qq[Error connecting app: $status] if !$status;

                        $cb->( Pcore::Util::Status->new( { status => 200 } ) );

                        return;
                    }
                );

                return;
            };

            my $approve_app_instance = sub ($app_instance_id) {
                $self->approve_app_instance(
                    $app_instance_id,
                    sub ( $status, $app_instance_token ) {
                        die qq[Error approving app: $status] if !$status;

                        P->file->write_bin( $app_instance_file, "$app_instance_id:$app_instance_token" );

                        $connect_app_instance->( $app_instance_id, $app_instance_token );

                        return;
                    }
                );

                return;
            };

            if ( !$app_instance_id ) {

                # register app on backend, get and init message broker
                $self->register_app_instance(
                    $self->app->name,
                    $self->app->desc,
                    "@{[$self->app->version]}",
                    P->sys->hostname,
                    {},    # handles

                    sub ( $status, $app_instance_id ) {
                        die qq[Error registering app: $status] if !$status;

                        P->file->write_bin( $app_instance_file, "$app_instance_id:" );

                        $approve_app_instance->($app_instance_id);

                        return;
                    }
                );
            }
            elsif ( !$app_instance_token ) {
                $approve_app_instance->($app_instance_id);
            }
            else {
                $connect_app_instance->( $app_instance_id, $app_instance_token );
            }

            return;
        }
    );

    return;
};

# USER
around get_user_by_id => sub ( $orig, $self, $user_id, $cb ) {
    if ( $self->{user_cache}->{$user_id} ) {
        $cb->( Pcore::Util::Status->new( { status => 200 } ), $self->{user_cache}->{$user_id} );
    }
    else {
        $self->$orig(
            $user_id,
            sub ( $status, $user = undef ) {
                if ($status) {
                    $self->{user_cache}->{$user_id} = $user;

                    $self->{username_id_cache}->{ $user->{username} } = $user_id;
                }

                $cb->( $status, $user );

                return;
            }
        );
    }

    return;
};

around get_user_by_name => sub ( $orig, $self, $username, $cb ) {
    if ( my $user_id = $self->{username_id_cache}->{$username} ) {
        $self->get_user_by_id( $user_id, $cb );
    }
    else {
        $self->$orig(
            $username,
            sub ( $status, $user = undef ) {
                if ($status) {
                    $self->{user_cache}->{ $user->{id} } = $user;

                    $self->{username_id_cache}->{$username} = $user->{id};
                }

                $cb->( $status, $user );

                return;
            }
        );
    }

    return;
};

around create_user => sub ( $orig, $self, $username, $password, $role_id, $cb ) {
    $self->$orig( $username, $password, $role_id, $cb );

    return;
};

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
