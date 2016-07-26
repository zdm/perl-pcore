package Pcore::API::Server::Role::Auth;

use Pcore -role;

with qw[Pcore::API::Server::Role];

sub _build_map ($self) {
    return {};
}

sub create_user ( $self, $username, $password, $cb ) {
    state $q1 = $self->dbh->query('INSERT OR IGNORE INTO api_user (username, password, enabled) VALUES (?, 1, 0)');

    state $q2 = $self->dbh->query('UPDATE api_user SET password = ?, enabled = 1 WHERE id = ?');

    if ( $q1->do( [$username] ) ) {
        my $id = $self->dbh->last_insert_id;

        $self->_hash_rpc->rpc_call(
            'create_scrypt',
            [$password],
            sub ($password_hash) {
                $q2->do( [ $password_hash, $id ] );

                $cb->($id);

                return;
            }
        );
    }
    else {

        # user already exists
        $cb->(undef);
    }

    return;
}

# TODO store uid inside token
sub create_token ( $self, $uid, $role_id, $cb ) {
    state $q1 = $self->dbh->query('INSERT OR IGNORE INTO api_token (id, token, uid, enabled) VALUES (?, ?, ?, 1)');

    state $generate_token;

    $generate_token //= sub ( $uid, $cb ) {
        my $token_id = P->random->bytes(32);

        my $token = substr $token_id, 0, 16, q[];

        $self->_hash_rpc->rpc_call(
            'create_scrypt',
            [$token],
            sub ($token_hash) {
                if ( !$q1->do( [ $token_id, $token_hash, $uid ] ) ) {

                    # token is not uniq.
                    $generate_token->( $uid, $cb );

                }
                else {
                    $cb->( P->data->to_b64_url( $token_id . $token ) );
                }

                return;
            }
        );

        return;
    };

    $generate_token->( $uid, $cb );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server::Role::Auth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
