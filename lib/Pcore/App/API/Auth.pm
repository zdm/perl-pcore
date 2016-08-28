package Pcore::App::API::Auth;

use Pcore -role;

requires qw[upload_api_map auth_password auth_token auth_method set_root_password create_user create_role set_user_password set_enable_user];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has remote_cache_id => ( is => 'ro', isa => HashRef, init_arg => undef );

has _auth_method_cache     => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has _auth_method_req_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

around auth_method => sub ( $orig, $self, $mid, $rid, $cb ) {
    state $cache_id = 'auth_method';

    # drop cache, if data was changed
    $self->{_auth_method_cache}->%* = () if $self->{remote_cache_id}->{$cache_id} != $self->{local_cache_id}->{$cache_id};

    my $id = "$rid\_$mid";

    if ( exists $self->{_auth_method_cache}->{$id} ) {
        $cb->( $self->{_auth_method_cache}->{$id} );
    }
    else {
        push $self->{_auth_method_req_cache}->{$id}->@*, $cb;

        return if $self->{_auth_method_req_cache}->{$id}->@* > 1;

        $self->$orig(
            $mid, $rid,
            sub ( $status, $auth ) {

                # cache result on success
                if ($status) {
                    $self->{_auth_method_cache}->{$id} = $auth;
                }
                else {
                    $auth = 0;
                }

                while ( my $cb = shift $self->{_auth_method_req_cache}->{$id}->@* ) {
                    $cb->($auth);
                }

                delete $self->{_auth_method_req_cache}->{$id};

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
## |    3 | 18                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
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
