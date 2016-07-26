package Pcore::API::Server::Auth;

use Pcore -class;

has uid     => ( is => 'ro', isa => PositiveInt, required => 1 );
has role_id => ( is => 'ro', isa => PositiveInt, required => 1 );

has allowed_methods => ( is => 'lazy', isa => HashRef, init_arg => undef );

# TODO resolve role_id -> methods
sub _build_allowed_methods ($self) {
    return {};
}

sub is_root ($self) {
    return $self->{uid} == 1;
}

sub api_call ( $self, $version, $class, $method, $data, $auth, $cb ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $version //= $self->default_version;

    my $on_finish = sub ( $status, $reason = undef, $result = undef ) {
        my $api_res = Pcore::API::Response->new( { status => $status, defined $reason ? ( reason => $reason ) : () } );

        $api_res->{result} = $result;

        $cb->($api_res) if $cb;

        $blocking_cv->($api_res) if $blocking_cv;

        return;
    };

    my $map = $self->{map}->{$version}->{$class};

    if ( !$map ) {
        $on_finish->( 404, q[API class was not found] );
    }
    elsif ( !exists $map->{method}->{$method} ) {
        $on_finish->( 404, q[API method was not found] );
    }
    else {

        # TODO check auth
        if (0) {
            $on_finish->( 401, q[Unauthorized] );
        }
        else {
            my $obj = bless { api => $self }, $map->{class};

            $obj->$method( $data, $on_finish );
        }
    }

    return defined $blocking_cv ? $blocking_cv->recv : ();
}

# ---------------------------------------
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
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 19                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server::Auth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
