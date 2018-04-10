package Pcore::App::API::LocalNoAuth;

use Pcore -class, -result;

with qw[Pcore::App::API];

sub init ( $self ) {
    return result 200;
}

# AUTHENTICATE
sub authenticate ( $self, $user_name_utf8, $token, $cb ) {
    $cb->( bless { app => $self->{app} }, 'Pcore::App::API::Auth' );

    return;
}

sub authenticate_private ( $self, $private_token, $cb ) {
    $cb->( bless { app => $self->{app} }, 'Pcore::App::API::Auth' );

    return;
}

sub do_authenticate_private ( $self, $private_token ) {
    return result [ 404, 'User not found' ];
}

# USER
sub create_user ( $self, $user_name, $password, $enabled, $permissions ) {

    # user already exists
    return result [ 400, 'Auth backend is not available' ];
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 12, 29               | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::LocalNoAuth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
