package Pcore::App::API;

use Pcore -role;
use Pcore::App::API::Map;
use Pcore::App::API::Request;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has app_id => ( is => 'lazy', isa => Str, init_arg => undef );
has auth => ( is => 'lazy', isa => ConsumerOf ['Pcore::App::API::Auth'], init_arg => 'undef' );
has map => ( is => 'lazy', isa => HashRef, init_arg => undef );

has _cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );    # API controllers cache

sub _build_app_id ($self) {
    return $self->{app}->app_id;
}

sub _build_auth ($self) {
    my $auth;

    if ( !ref $self->{app}->{auth} ) {
        require Pcore::App::API::Auth::Local;

        $auth = Pcore::App::API::Auth::Local->new( { api => $self, dbh => P->handle( $self->{app}->{auth} ) } );
    }
    elsif ( $self->{app}->{auth}->does('Pcore::DBH') ) {
        $auth = Pcore::App::API::Auth::Local->new( { api => $self, dbh => $self->{app}->{auth} } );
    }
    else {
        $auth = $self->{app}->{auth};
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

        if ( !$class_name->does('Pcore::App::API::Role') ) {
            delete $controllers->{$class_name};

            say qq["$class_name" is not a consumer of "Pcore::App::API::Role"];

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
                my $api_request = bless {
                    api     => $self,
                    uid     => $uid,
                    role_id => 1,
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

# TODO fix authentication
sub auth_token ( $self, $token_b64, $cb ) {
    return $self->auth->auth_token(
        $token_b64,
        sub ($uid) {
            if (1) {

                # if ($uid) {
                my $api_request = bless {
                    api     => $self,
                    uid     => $uid // 1,
                    role_id => 1,
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
## |    3 | 68, 96, 100          | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 59                   | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
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
