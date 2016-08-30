package Pcore::App::API;

use Pcore -role;
use Pcore::App::API::Map;
use Pcore::App::API::Auth;
use Pcore::App::API::Request;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has auth => ( is => 'lazy', isa => InstanceOf ['Pcore::App::API::Auth'], init_arg => undef );
has map  => ( is => 'lazy', isa => InstanceOf ['Pcore::App::API::Map'],  init_arg => undef );

sub _build_auth ($self) {
    return Pcore::App::API::Auth->new( { app => $self->app } );
}

sub _build_map ($self) {

    # use class name as string to avoid conflict with Type::Standard Map subroutine, exported to Pcore::App::API
    return "Pcore::App::API::Map"->new( { app => $self->app } );
}

# TODO combine token and password auth???

# AUTH BACKEND METHODS
# # TODO blocking / not blocking
sub auth_password ( $self, $username, $password, $cb ) {
    return $self->auth->auth_password(
        $username,
        $password,
        sub ($uid) {
            if ($uid) {
                my $api_request = bless {
                    api => $self,
                    uid => $uid,
                    rid => 1,
                  },
                  'Pcore::App::API::Request';

                $cb->($api_request);
            }
            else {
                $cb->(undef);
            }

            return;
        }
    );
}

# TODO blocking / not blocking
# TODO fix authentication
sub auth_token ( $self, $token_b64, $cb ) {
    return $self->auth->auth_token(
        $token_b64,
        sub ($uid) {
            if (1) {

                # if ($uid) {
                my $api_request = bless {
                    api => $self,
                    uid => $uid // 1,
                    rid => 1,
                  },
                  'Pcore::App::API::Request';

                $cb->($api_request);
            }
            else {
                $cb->(undef);
            }

            return;
        }
    );
}

sub upload_api_map ( $self ) {
    return $self->auth->upload_api_map( $self->map );
}

# TODO blocking / not blocking
sub set_root_password ( $self, $password = undef ) {
    return $self->auth->set_root_password($password);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 20                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
