package Pcore::App::API::Auth::Descriptor;

use Pcore -const, -class, -export => { CONST => [qw[$TOKEN_TYPE_USER_PASSWORD $TOKEN_TYPE_APP_INSTANCE_TOKEN $TOKEN_TYPE_USER_TOKEN]] };
use Pcore::Util::Data qw[to_b64_url from_b64];
use Pcore::Util::Digest qw[sha1];
use Pcore::Util::Text qw[encode_utf8];

const our $TOKEN_TYPE_USER_PASSWORD      => 1;
const our $TOKEN_TYPE_APP_INSTANCE_TOKEN => 2;
const our $TOKEN_TYPE_USER_TOKEN         => 3;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has id => ( is => 'ro', isa => Str, init_arg => undef );
has token_type => ( is => 'ro', isa => Enum [ $TOKEN_TYPE_USER_PASSWORD, $TOKEN_TYPE_APP_INSTANCE_TOKEN, $TOKEN_TYPE_USER_TOKEN ], init_arg => undef );
has private_token => ( is => 'ro', isa => Str, init_arg => undef );
has user_name       => ( is => 'ro', isa => Maybe [Str],         init_arg => undef );
has app_instance_id => ( is => 'ro', isa => Maybe [PositiveInt], init_arg => undef );
has user_token_id   => ( is => 'ro', isa => Maybe [PositiveInt], init_arg => undef );

has user_id       => ( is => 'ro', isa => Maybe [PositiveInt], init_arg => undef );
has app_id        => ( is => 'ro', isa => Maybe [PositiveInt], init_arg => undef );
has authenticated => ( is => 'ro', isa => Maybe [Bool],        init_arg => undef );
has enabled       => ( is => 'ro', isa => Maybe [Bool],        init_arg => undef );
has permissions   => ( is => 'ro', isa => Maybe [HashRef],     init_arg => undef );

around new => sub ( $orig, $self, $app, $token, $user_name_utf8 ) {
    my $args;

    # detect auth type
    if ($user_name_utf8) {
        my $user_name = eval {
            encode_utf8 $token;
            encode_utf8 $user_name_utf8;
        };

        # error decoding token
        reture if $@;

        $args = {
            private_token => sha1 $token . $user_name,
            token_type    => $TOKEN_TYPE_USER_PASSWORD,
            user_name     => $user_name_utf8,
        };

        $args->{id} = "$args->{token_type}-$user_name-$args->{private_token}";
    }
    else {

        # decode token
        ( $args->{token_type}, my $token_id ) = eval {
            encode_utf8 $token;
            unpack 'CL', from_b64 $token;
        };

        # error decoding token
        return if $@;

        # token is invalid
        if ( $args->{token_type} == $TOKEN_TYPE_APP_INSTANCE_TOKEN ) {
            $args->{app_instnce_id} = $token_id;
        }
        elsif ( $args->{token_type} == $TOKEN_TYPE_USER_TOKEN ) {
            $args->{user_token_id} = $token_id;
        }

        # invalid token type
        else {
            return;
        }

        $args->{private_token} = sha1 $token . $token_id;

        $args->{id} = "$args->{token_type}-$token_id-$args->{private_token}";
    }

    return bless $args, $self;
};

sub authenticate ( $self, $cb ) {
    my @args;

    # authenticated
    if ( defined $self->{authenticated} ) {
        if ( !$self->{authenticated} ) {
            $cb->(undef);
        }
    }
    else {
        push @args, $self->{private_token};
    }

    # enabled
    if ( defined $self->{enabled} ) {
        if ( !$self->{enabled} ) {
            $cb->(undef);
        }
    }
    else {
        push @args, 1;
    }

    # permissions
    if ( defined $self->{permissions} ) {
        $cb->( $self->{permissions} );
    }
    else {
        push @args, 1;
    }

    my $method = $self->{auth_method};

    $self->{app}->{api}->{backend}->$method(
        $self->{authenticated} ? undef : $self->{private_token},    # authenticate token
        $self->{enabled}       ? undef : 1,                         # check token enabled
        $self->{permissions}   ? undef : 1,                         # get token permissions
    );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Descriptor

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
