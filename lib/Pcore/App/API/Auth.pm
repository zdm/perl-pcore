package Pcore::App::API::Auth;

use Pcore -class, -status;
use Pcore::App::API qw[:CONST];
use Pcore::App::API::Auth::Request;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has id => ( is => 'ro', isa => Str, required => 1 );
has token_type => ( is => 'ro', isa => Enum [ keys $TOKEN_TYPE->%* ], required => 1 );
has token_id => ( is => 'ro', isa => Str, required => 1 );

has is_user => ( is => 'ro', isa => Bool, required => 1 );
has is_root => ( is => 'ro', isa => Bool, required => 1 );
has user_id   => ( is => 'ro', isa => Maybe [Str], required => 1 );
has user_name => ( is => 'ro', isa => Maybe [Str], required => 1 );

has is_app => ( is => 'ro', isa => Bool, required => 1 );
has app_id          => ( is => 'ro', isa => Maybe [Str], required => 1 );
has app_instance_id => ( is => 'ro', isa => Maybe [Str], required => 1 );

has permissions => ( is => 'ro', isa => Maybe [HashRef], required => 1 );

sub api_call ( $self, $method_id, @ ) {
    my ( $cb, $args );

    # parse $args and $cb
    if ( ref $_[-1] eq 'CODE' ) {
        $cb = $_[-1];

        $args = [ splice @_, 2, -1 ] if @_ > 3;
    }
    else {
        $args = [ splice @_, 2 ] if @_ > 2;
    }

    return api_call_arrayref( $self, $method_id, $args, $cb );
}

sub api_call_arrayref ( $self, $method_id, $args, $cb = undef ) {
    my $map = $self->{app}->{api}->{map};

    # find method
    my $method_cfg = $map->{method}->{$method_id};

    if ( !$method_cfg ) {
        $cb->( status [ 404, qq[API method "$method_id" was not found] ] ) if $cb;

        return;
    }

    my $api_call = sub {
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

        return;
    };

    # user is root, method authentication is not required
    if ( $self->{is_root} ) {
        $api_call->();
    }

    # user is not root, need to perform authorization
    else {

        # perform authorization
        $self->_authorize(
            sub ($permissions) {

                # user is disabled or permisisons error
                if ( !$permissions ) {
                    $cb->( status [ 403, q[Unauthorized access] ] ) if $cb;

                    return;
                }

                # method has no permissions, api call is allowed for any authenticated and authorized user
                if ( !$method_cfg->{permissions} ) {
                    $api_call->();

                    return;
                }

                # method has permissions, compare method roles with authorized roles
                for my $role ( $method_cfg->{permissions}->@* ) {
                    if ( exists $permissions->{$role} ) {
                        $api_call->();

                        return;
                    }
                }

                # api call is permitted
                $cb->( status [ 403, qq[Unauthorized access to API method "$method_id"] ] ) if $cb;

                return;
            }
        );
    }

    return;
}

sub _authorize ( $self, $cb ) {
    my $cache = $self->{app}->{api}->{auth_cache}->{auth};

    # token was removed, token is not authenticated
    if ( !exists $cache->{ $self->{id} } ) {
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
                    $self->{permissions} = $res->{result}->{auth}->{permisions};

                    $cb->( $self->{permissions} );
                }
            }

            return;
        }
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 65                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
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
