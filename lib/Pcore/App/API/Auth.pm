package Pcore::App::API::Auth;

use Pcore -class;
use Pcore::App::API qw[:CONST];
use Pcore::App::API::Auth::Request;
use Pcore::Util::Status::Keyword qw[status];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has id => ( is => 'ro', isa => Str, required => 1 );
has token_type => ( is => 'ro', isa => Enum [ $TOKEN_TYPE_USER_PASSWORD, $TOKEN_TYPE_APP_INSTANCE_TOKEN, $TOKEN_TYPE_USER_TOKEN ], required => 1 );
has token_id => ( is => 'lazy', isa => Str, required => 1 );

has enabled     => ( is => 'ro',   isa => Maybe [Bool],    required => 1 );
has permissions => ( is => 'lazy', isa => Maybe [HashRef], required => 1 );

has user_id         => ( is => 'ro', isa => Maybe [PositiveInt] );
has user_name       => ( is => 'ro', isa => Maybe [Str] );
has user_token_id   => ( is => 'ro', isa => Maybe [PositiveInt] );
has app_id          => ( is => 'ro', isa => Maybe [PositiveInt] );
has app_instance_id => ( is => 'ro', isa => Maybe [PositiveInt] );

sub is_root ($self) {
    return $self->{user_id} && $self->{user_id} == 1;
}

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
            auth       => $self,
            _cb        => $cb,
            _responded => 0,
          },
          'Pcore::App::API::Auth::Request';

        # call method
        eval { $obj->$method_name( $req, $args ? $args->@* : undef ) };

        $@->sendlog if $@;

        return;
    };

    # user is root, method authentication is not required
    if ( $self->{user_id} && $self->{user_id} == 1 ) {
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
    my $cache = $self->{app}->{api}->{_auth_cache};

    # user token was removed, token is not authenticated
    if ( $self->{token_type} == $TOKEN_TYPE_USER_TOKEN ) {
        if ( !exists $cache->{ $self->{id} } ) {
            $cb->(undef);

            return;
        }
    }

    # auth enabled status is defined
    if ( defined $self->{enabled} ) {

        # auth is disabled
        if ( !$self->{enabled} ) {
            $cb->(undef);

            return;
        }

        # auth is enabled and has permissions defined
        elsif ( defined $self->{permissions} ) {
            $cb->( $self->{permissions} );

            return;
        }
    }

    # authenticate token on backend
    $self->{backend}->auth_token(
        $self->{app}->{instance_id},
        $self->{token_type},
        $self->{token_id},
        undef,    # do not validate token
        sub ( $status, $auth, $tags ) {
            if ( !$status ) {
                $cb->(undef);
            }
            else {

                # user token was removed, token is not authenticated
                if ( $self->{token_type} == $TOKEN_TYPE_USER_TOKEN && !$cache->{ $self->{id} } ) {
                    $cb->(undef);

                    return;
                }

                $self->{enabled}     = $auth->{enabled};
                $self->{permissions} = $auth->{permissions};

                if ( $self->{enabled} ) {
                    $cb->( $self->{permissions} );
                }
                else {
                    $cb->(undef);
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
## |    3 | 69                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
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
