package Pcore::App::API::Auth;

use Pcore -role;

requires qw[auth_password auth_token auth_method set_root_password upload_api_map];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has _auth_cache_id => ( is => 'ro', isa => PositiveInt, default => 0, init_arg => undef );
has _auth_method_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

around auth_method => sub ( $orig, $self, $mid, $rid, $cb ) {
    if ( exists $self->{_auth_method_cache}->{$rid}->{$mid} ) {
        $cb->( $self->{_auth_method_cache}->{$rid}->{$mid} );
    }
    else {
        $self->$orig(
            $mid, $rid,
            sub ( $status, $auth, $auth_cache_id ) {
                if ($status) {

                    # drop auth cache, if cache tag was changed
                    if ( $self->{_auth_cache_id} != $auth_cache_id ) {
                        $self->{_auth_cache_id} == $auth_cache_id;

                        $self->{_auth_method_cache}->%* = ();
                    }

                    $self->{_auth_method_cache}->{$rid}->{$mid} = $auth;

                    $cb->($auth);
                }
                else {
                    $cb->(0);
                }

                return;
            }
        );
    }

    return;
};

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 26                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
