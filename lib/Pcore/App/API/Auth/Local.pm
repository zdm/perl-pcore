package Pcore::App::API::Auth::Local;

use Pcore -role;
use Pcore::App::API::RPC::Hash;
use Pcore::Util::Hash::RandKey;
use Pcore::Util::Status;

with qw[Pcore::App::API::Auth];

requires qw[_ddl_upgrade _build_local_cache_id update_local_cache_id];

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

has local_cache_id => ( is => 'lazy', isa => HashRef, init_arg => undef );

has _hash_rpc => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );

# BUILD
around BUILD => sub ( $orig, $self, $args ) {
    $self->_ddl_upgrade;

    $self->local_cache_id;

    return $self->$orig($args);
};

# CACHE
around _build_local_cache_id => sub ( $orig, $self ) {
    my $cache = $self->$orig;

    $self->{remote_cache_id} = $cache;

    return $cache;
};

around update_local_cache_id => sub ( $orig, $self, $cache_id ) {
    die q[Unknown API cache id] if !exists $self->{local_cache_id}->{$cache_id};

    $self->{local_cache_id}->{$cache_id}++;

    $self->$orig( $cache_id, $self->{local_cache_id}->{$cache_id} );

    return;
};

# HASH
sub _build__hash_rpc($self) {
    return P->pm->run_rpc(
        'Pcore::App::API::RPC::Hash',
        workers   => 1,
        buildargs => {
            scrypt_n   => 16_384,
            scrypt_r   => 8,
            scrypt_p   => 1,
            scrypt_len => 32,
        },
    );
}

# TODO implement cache size
sub _verify_hash ( $self, $str, $hash, $cb ) {
    $str = P->text->encode_utf8($str);

    my $id = $str . $hash;

    if ( exists $self->{_hash_cache}->{$id} ) {
        $cb->(1);
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_scrypt',
            $str, $hash,
            sub ( $status, $match ) {
                $self->{_hash_cache}->{$id} = undef;

                $cb->($match);

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
## |    3 | 62                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_verify_hash' declared but not used |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
