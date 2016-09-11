package Pcore::App::API::Request;

use Pcore -class;
use Pcore::Util::Status;
use Pcore::Util::Scalar qw[blessed];

use overload    #
  q[&{}] => sub ( $self, @ ) {
    return sub { return _respond( $self, @_ ) };
  },
  bool => sub {
    return 1;
  },
  fallback => undef;

has api => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API'], required => 1 );
has auth_id => ( is => 'ro', isa => Str, required => 1 );    # user id

has _cb => ( is => 'ro', isa => Maybe [CodeRef], init_arg => undef );
has _responded => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # already responded

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && !$self->{_responded} && $self->{_cb} ) {

        # API request object destroyed without return any result, this is possible run-time error in AE callback
        _respond( $self, 500 );
    }

    return;
}

sub is_root ($self) {
    return $self->{uid} == 1;
}

sub api_call ( $self, $method_id, @ ) {
    my ( $cb, $args );

    if ( ref $_[-1] eq 'CODE' ) {
        $cb = $_[-1];

        $args = [ splice @_, 2, -1 ] if @_ > 3;
    }
    else {
        $args = [ splice @_, 2 ] if @_ > 2;
    }

    return api_call_arrayref( $self, $method_id, $args, $cb );
}

# TODO blocking call, return @arrs if wantarray
sub api_call_arrayref ( $self, $method_id, $args, $cb = undef ) {

    # get a clone
    $self = bless { $self->%* }, __PACKAGE__;

    $self->{_responded} = 0;

    $self->{_cb} = $cb;

    my $method_cfg = $self->{api}->{map}->{method}->{$method_id};

    # find method
    return _respond( $self, [ 404, qq[API method "$method_id" was not found] ] ) if !$method_cfg;

    my $api_call = sub {
        my $obj = $self->{api}->{map}->{obj}->{ $method_cfg->{class_name} };

        my $method_name = $method_cfg->{local_method_name};

        # call method
        eval { $obj->$method_name( $self, $args ? $args->@* : undef ) };

        $@->sendlog if $@;

        return;
    };

    # user is root, method authentication is not required
    # TODO detect root user
    if ( $self->{uid} == 1 ) {
        $api_call->();
    }

    # user is not root, need to authorize method
    else {

        # perform authorization
        $self->{api}->authorize(
            $self->{auth_id},
            sub ($permissions) {
                if ( !$permissions ) {
                    _respond( $self, [ 403, qq[Unauthorized access] ] );
                }
                else {
                    my $allowed;

                    # method has permissions, compare method roles with authorized roles
                    if ( $method_cfg->{permissions} ) {
                        for my $role ( $method_cfg->{permissions}->@* ) {
                            if ( exists $permissions->{$role} ) {
                                $allowed = 1;

                                last;
                            }
                        }
                    }

                    # method has no permissions, api call is allowed for any authenticated user
                    else {
                        $allowed = 1;
                    }

                    # call is allowed
                    if ($allowed) {
                        $api_call->();
                    }

                    # api call is permitted
                    else {
                        _respond( $self, [ 403, qq[Unauthorized access to API method "$method_id"] ] );
                    }
                }

                return;
            }
        );
    }

    return;
}

sub _respond ( $self, $status, @args ) {
    die q[Already responded] if $self->{_responded};

    $self->{_responded} = 1;

    # remove callback
    my $cb = delete $self->{_cb};

    # return response, if callback is defined
    if ($cb) {
        $status = Pcore::Util::Status->new( { status => $status } ) if !blessed $status;

        $cb->( $status, @args );
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
## |    3 | 74                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 95                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
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
