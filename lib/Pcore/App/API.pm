package Pcore::App::API;

use Pcore -role;
use Pcore::App::API::Map;
use Pcore::App::API::Auth;
use Pcore::App::API::Request;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has auth => ( is => 'lazy', isa => ConsumerOf ['Pcore::App::API::Auth'], init_arg => undef );
has map  => ( is => 'lazy', isa => InstanceOf ['Pcore::App::API::Map'],  init_arg => undef );

sub _build_auth ($self) {
    return Pcore::App::API::Auth->new( { app => $self->app } );
}

sub _build_map ($self) {

    # use class name as string to avoid conflict with Type::Standard Map subroutine, exported to Pcore::App::API
    return "Pcore::App::API::Map"->new( { app => $self->app } );
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
