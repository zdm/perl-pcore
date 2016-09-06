package Pcore::App::API::Backend::Local;

use Pcore -role, -const;
use Pcore::Util::Status::Keyword qw[status];
use Pcore::Util::Hash::RandKey;
use Pcore::Util::Data qw[to_b64_url from_b64];

with qw[Pcore::App::API::Backend];

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

has _hash_rpc => ( is => 'ro', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );
has _hash_cache_size => ( is => 'ro', isa => PositiveInt, default => 10_000 );

const our $TOKEN_TYPE_APP_INSTANCE => 1;
const our $TOKEN_TYPE_USER         => 2;

sub _build_is_local ($self) {
    return 1;
}

sub _build_host ($self) {
    return 'local';
}

around init => sub ( $orig, $self, $cb ) {
    $self->{_hash_rpc} = P->pm->run_rpc(
        'Pcore::App::API::RPC::Hash',
        workers   => undef,
        buildargs => {
            scrypt_n   => 16_384,
            scrypt_r   => 8,
            scrypt_p   => 1,
            scrypt_len => 32,
        },
    );

    return $self->$orig($cb);
};

sub register_app_instance ( $self, $app_name, $app_desc, $instance_version, $instance_host, $roles, $permissions, $cb ) {
    my $dbh = $self->dbh;

    $dbh->begin_work;

    $self->create_app(
        $app_name,
        $app_desc,
        sub ( $status, $app_id ) {
            $self->create_app_instance(
                $app_id,
                $instance_host,
                sub ( $status, $instance_id ) {

                    # app instance creation error
                    if ( !$status ) {
                        $dbh->rollback;

                        $cb->( $status, undef );
                    }

                    # app instance created
                    else {
                        my $cv = AE::cv sub {
                            return;
                        };

                        # store app roles
                        for my $role_name ( keys $roles->%* ) {
                            $cv->begin;

                            $self->create_app_role(
                                $app_id,
                                $role_name,
                                $roles->{$role_name},
                                sub ( $status, $role_id ) {
                                    $cv->end;

                                    return;
                                }
                            );
                        }
                    }

                    return;
                }
            );

            return;
        }
    );

    my $new_app;

    my $app_id;

    # app already exists
    if ( my $app = $dbh->selectrow( q[SELECT * FROM api_app WHERE name = ?], [$app_name] ) ) {
        $app_id = $app->{id};
    }

    # create new app
    else {
        $dbh->do( q[INSERT INTO api_app (name, desc, enabled) VALUES (?, ?, ?)], [ $app_name, $app_desc, 1 ] );

        $app_id = $dbh->last_insert_id;

        $new_app = 1;
    }

    $dbh->do( q[INSERT INTO api_app_instance (app_id, version, host, created_ts, approved, enabled) VALUES (?, ?, ?, ?, ?, ?)], [ $app_id, $instance_version, $instance_host, time, 0, 0 ] );

    my $app_instance_id = $dbh->last_insert_id;

    # TODO store roles, permissions
    if ($new_app) {

        # add app roles
        for my $role ( keys $roles->%* ) {
            $dbh->do( q[INSERT OR IGNORE INTO api_app_role (app_id, name, desc) VALUES (?, ?, ?)], [ $app_id, $role, $roles->{$role} ] );
        }
    }

    $dbh->commit;

    $cb->( status 200, $app_instance_id );

    return;
}

# APP TOKEN
sub generate_app_instance_token ( $self, $app_instance_id, $cb ) {

    # generate random token
    my $token = P->random->bytes(48);

    # add token type, app instance id
    $token = to_b64_url pack( 'C', $TOKEN_TYPE_APP_INSTANCE ) . pack( 'L', $app_instance_id ) . $token;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $token,
        sub ( $status, $hash ) {
            $cb->( $status, $token, $hash );

            return;
        }
    );

    return;
}

sub validate_app_instance_token_hash ( $self, $token, $hash, $cb ) {
    $self->verify_hash( $token, $hash, $cb );

    return;
}

# USER TOKEN
sub generate_user_token ( $self, $token_id, $user_id, $role_id, $cb ) {

    # generate random token
    my $token = P->random->bytes(48);

    # add token type, app instance id
    $token = to_b64_url pack( 'C', $TOKEN_TYPE_USER ) . pack( 'L', $token_id ) . $token;

    my $private_token = $token . $user_id . $role_id;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $private_token,
        sub ( $status, $hash ) {
            $cb->( $status, $token, $hash );

            return;
        }
    );

    return;
}

sub validate_user_token_hash ( $self, $token, $hash, $user_id, $role_id, $cb ) {
    my $private_token = $token . $user_id . $role_id;

    $self->verify_hash( $private_token, $hash, $cb );

    return;
}

# USER PASSWORD
sub generate_user_password_hash ( $self, $password, $user_id, $cb ) {
    my $private_token = $password . $user_id;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $private_token,
        sub ( $status, $hash ) {
            $cb->( $status, $hash );

            return;
        }
    );

    return;
}

sub validate_user_password_hash ( $self, $password, $hash, $user_id, $cb ) {
    my $private_token = $password . $user_id;

    $self->verify_hash( $private_token, $hash, $cb );

    return;
}

# HASH
# TODO limit cache size
sub verify_hash ( $self, $token, $hash, $cb ) {
    my $cache_id = "$hash-$token";

    if ( exists $self->{_hash_cache}->{$cache_id} ) {
        $cb->( $self->{_hash_cache}->{$cache_id} );
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_scrypt',
            $token, $hash,
            sub ( $rpc_status, $match ) {
                my $status = $match ? status 200 : status 400;

                $self->{_hash_cache}->{$cache_id} = $status;

                $cb->($status);

                return;
            }
        );
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 42, 161, 184, 209    | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
