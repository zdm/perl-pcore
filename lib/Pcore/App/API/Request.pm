package Pcore::App::API::Request;

use Pcore -class;

use overload    #
  q[&{}] => sub ( $self, @ ) {
    use subs qw[write];

    return sub { return write( $self, @_ ) };
  },
  bool => sub {
    return 1;
  },
  fallback => undef;

has api => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API'], required => 1 );
has uid     => ( is => 'ro', isa => PositiveInt, required => 1 );
has role_id => ( is => 'ro', isa => PositiveInt, required => 1 );

has allowed_methods => ( is => 'lazy', isa => HashRef, init_arg => undef );

has _cb => ( is => 'ro', isa => Maybe [CodeRef], init_arg => undef );
has _response_status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # already responded

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && !$self->{_response_status} && $self->{_cb} ) {

        # API request object destroyed without return any result, this is possible run-time error in AE callback
        $self->{_cb}->(500);
    }

    return;
}

# TODO resolve role_id -> methods
sub _build_allowed_methods ($self) {
    my $methods->@{ keys $self->api->map->%* } = ();

    return $methods;
}

sub is_root ($self) {
    return $self->{uid} == 1;
}

sub api_call ( $self, $method_id, $args, $cb = undef ) {

    # remember cb, if defined
    $self->{_cb} = $cb;

    my $method_cfg = $self->{api}->map->{$method_id};

    return $self->write( [ 404, qq[API method "$method_id" was not found] ] ) if !$method_cfg;

    return $self->write( [ 403, qq[Unauthorized access to API method "$method_id"] ] ) if $self->{uid} != 1 && !exists $self->allowed_methods->{$method_id};

    my $ctrl = $self->{api}->{_cache}->{$method_id} //= $method_cfg->{class_name}->new( { app => $self->{api}->{app} } );

    my $method_name = $method_cfg->{method_name};

    eval { $ctrl->$method_name( $self, $args ? $args->@* : undef ) };

    $@->sendlog if $@;

    return;
}

sub write ( $self, $status, $data = undef ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    die q[Already responded] if $self->{_response_status};

    $self->{_response_status} = 1;

    # remove callback
    my $cb = delete $self->{_cb};

    # return response, if callback is defined
    $cb->( $status, $data ) if $cb;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 39                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 63                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 9                    | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
