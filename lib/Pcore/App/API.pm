package Pcore::App::API;

use Pcore -role;
use Pcore::API::Response;
use Pcore::API::Server::Session;

has app_id => ( is => 'ro', isa => Str, required => 1 );
has _auth => ( is => 'ro', isa => Str | ConsumerOf ['Pcore::DBH'] | ConsumerOf ['Pcore::API::Server::Auth'], required => 1, init_arg => 'auth' );

has auth => ( is => 'lazy', isa => ConsumerOf ['Pcore::API::Server::Auth'], init_arg => 'undef' );
has map => ( is => 'lazy', isa => HashRef, init_arg => undef );

sub _build_auth ($self) {
    my $auth;

    if ( !ref $self->{_auth} ) {
        require Pcore::API::Server::Auth::Local;

        $auth = Pcore::API::Server::Auth::Local->new( { api => $self, dbh => P->handle( $self->{_auth} ) } );
    }
    elsif ( $self->{_auth}->does('Pcore::DBH') ) {
        $auth = Pcore::API::Server::Auth::Local->new( { api => $self, dbh => $self->{_auth} } );
    }
    else {
        $auth = $self->{_auth};

        $self->{_auth}->{api} = $self;
    }

    return $auth;
}

sub _build_map ($self) {
    my $map = {};

    my $ns_path = ref($self) =~ s[::][/]smgr;

    my $controllers = {};

    # scan namespace, find and preload controllers
    for my $path ( grep { !ref } @INC ) {
        if ( -d "$path/$ns_path" ) {
            my $guard = P->file->chdir("$path/$ns_path");

            P->file->find(
                "$path/$ns_path",
                abs => 0,
                dir => 0,
                sub ($path) {
                    if ( $path->suffix eq 'pm' ) {
                        my $route = $path->dirname . $path->filename_base;

                        my $class = "$ns_path/$route" =~ s[/][::]smgr;

                        $controllers->{$class} = P->text->to_snake_case( $route, delim => '-', split => '/', join => '/' );
                    }

                    return;
                }
            );
        }
    }

    for my $class_name ( sort keys $controllers->%* ) {
        P->class->load($class_name);

        my $class_path = $controllers->{$class_name};

        if ( !$class_name->does('Pcore::API::Server::Role') ) {
            delete $controllers->{$class_name};

            say qq["$class_name" is not a consumer of "Pcore::API::Server::Class"];

            next;
        }

        my $version;

        if ( $class_path =~ s[\Av(\d+)/][]sm ) {
            $version = $1;
        }
        else {
            say qq[Can not determine API version "$class_name"];

            next;
        }

        my $obj = bless { api => $self }, $class_name;

        my $obj_map = $obj->map;

        for my $method ( keys $obj_map->%* ) {
            my $method_id = qq[/v$version/$class_path/$method];

            $map->{$method_id} = {
                $obj_map->{$method}->%*,
                id          => $method_id,
                version     => "v$version",
                class_name  => $class_name,
                class_path  => $class_path,
                method_name => $method,
            };

            # validate api method configuration
            die qq[API method "$method_id" requires description] if !$map->{$method_id}->{desc};
        }
    }

    return $map;
}

# AUTH BACKEND METHODS
sub auth_password ( $self, $username, $password, $cb ) {
    return $self->auth->auth_password(
        $username,
        $password,
        sub ($uid) {
            if ($uid) {
                $cb->( Pcore::API::Server::Session->new( { api => $self, uid => $uid, role_id => 1 } ) );
            }
            else {
                $cb->(undef);
            }

            return;
        }
    );
}

sub auth_token ( $self, $token_b64, $cb ) {
    return $self->auth->auth_token(
        $token_b64,
        sub ($uid) {
            if ($uid) {
                $cb->( Pcore::API::Server::Session->new( { api => $self, uid => $uid, role_id => 1 } ) );
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
## |    3 | 64, 92, 96           | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 55                   | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
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
