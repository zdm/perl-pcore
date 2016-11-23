package Pcore::App::API::Auth;

use Pcore -class, -result;
use Pcore::App::API qw[:CONST];
use Pcore::App::API::Auth::Request;
use Pcore::Util::Scalar qw[blessed];

use overload    #
  q[bool] => sub {
    return $_[0]->{id} && $_[0]->{app}->{api}->{auth_cache}->{auth}->{ $_[0]->{id} };
  },
  fallback => undef;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has id         => ( is => 'ro', isa => Maybe [Str] );
has token_type => ( is => 'ro', isa => Maybe [ Enum [ keys $TOKEN_TYPE->%* ] ] );
has token_id   => ( is => 'ro', isa => Maybe [Str] );

has is_user   => ( is => 'ro', isa => Bool );
has is_root   => ( is => 'ro', isa => Bool );
has user_id   => ( is => 'ro', isa => Maybe [Str] );
has user_name => ( is => 'ro', isa => Maybe [Str] );

has is_app          => ( is => 'ro', isa => Bool );
has app_id          => ( is => 'ro', isa => Maybe [Str] );
has app_instance_id => ( is => 'ro', isa => Maybe [Str] );

has permissions => ( is => 'ro', isa => Maybe [HashRef] );

sub api_can_call ( $self, $method_id, $cb ) {
    my $map = $self->{app}->{api}->{map};

    # find method
    my $method_cfg = $map->{method}->{$method_id};

    # methodd wasn't found
    if ( !$method_cfg ) {
        $cb->( result 404 );

        return;
    }

    # user is root, method authentication is not required
    if ( $self->{is_root} ) {
        $cb->( result 200 );
    }

    # method has no permissions, authorization is not required
    elsif ( !$method_cfg->{permissions} ) {
        $cb->( result 200 );
    }

    # user is not root, need to perform authorization
    else {

        # perform authorization
        $self->_authorize(
            sub ($permissions) {

                # user is disabled or permisisons error, api call is forbidden
                if ( !$permissions ) {
                    $cb->( result 403 );

                    return;
                }

                # method has permissions, compare method roles with authorized roles
                for my $role ( $method_cfg->{permissions}->@* ) {
                    if ( exists $permissions->{$role} ) {
                        $cb->( result 200 );

                        return;
                    }
                }

                # api call is forbidden
                $cb->( result 403 );

                return;
            }
        );
    }

    return;
}

sub api_call ( $self, $method_id, @ ) {
    my ( $cb, $args );

    # parse $args and $cb
    if ( ref $_[-1] eq 'CODE' ) {
        $cb = $_[-1];

        $args = [ splice @_, 2, -1 ] if @_ > 3;
    }
    elsif ( blessed $_[-1] && $_[-1]->isa('Pcore::App::API::Auth::Request') ) {
        $cb = $_[-1];

        $args = [ splice @_, 2, -1 ] if @_ > 3;
    }
    else {
        $args = [ splice @_, 2 ] if @_ > 2;
    }

    return api_call_arrayref( $self, $method_id, $args, $cb );
}

sub api_call_arrayref ( $self, $method_id, $args, $cb = undef ) {
    $self->api_can_call(
        $method_id,
        sub ($can_call) {
            if ( !$can_call ) {
                $cb->($can_call) if $cb;
            }
            else {
                my $map = $self->{app}->{api}->{map};

                # get method
                my $method_cfg = $map->{method}->{$method_id};

                my $obj = $map->{obj}->{ $method_cfg->{class_name} };

                my $method_name = $method_cfg->{local_method_name};

                # create API request
                my $req = bless {
                    auth => $self,
                    _cb  => $cb,
                  },
                  'Pcore::App::API::Auth::Request';

                # call method
                eval { $obj->$method_name( $req, $args ? $args->@* : () ) };

                $@->sendlog if $@;
            }

            return;
        }
    );

    return;
}

sub _authorize ( $self, $cb ) {
    my $cache = $self->{app}->{api}->{auth_cache}->{auth};

    # token was removed, token is not authenticated
    if ( !$self->{id} || !exists $cache->{ $self->{id} } ) {
        $cb->(undef);

        return;
    }

    # auth is enabled and has permissions defined
    if ( defined $self->{permissions} ) {
        $cb->( $self->{permissions} );

        return;
    }

    # authorize on backend
    $self->{backend}->auth_token(
        $self->{app}->{instance_id},
        $self->{token_type},
        $self->{token_id},
        undef,    # do not validate token

        sub ( $res ) {

            # get permissions error
            if ( !$res ) {
                $cb->(undef);
            }

            # permissions retrieved
            else {

                # token was removed, token is not authenticated
                if ( !exists $cache->{ $self->{id} } ) {
                    $cb->(undef);
                }
                else {
                    $self->{permissions} = $res->{data}->{auth}->{permisions};

                    $cb->( $self->{permissions} );
                }
            }

            return;
        }
    );

    return;
}

sub TO_DATA ($self) {
    die q[Direct auth object serialization is impossible for security reasons];
}

sub extdirect_map ( $self, $ver, $cb ) {
    $self->{app}->{api}->{map}->extdirect_map( $self, $ver, $cb );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 134                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
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
