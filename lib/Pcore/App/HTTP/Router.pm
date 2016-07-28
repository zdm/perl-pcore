package Pcore::App::HTTP::Router;

use Pcore -class;

with qw[Pcore::HTTP::Server::Router];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App::HTTP'], required => 1 );

has route => ( is => 'lazy', isa => HashRef, init_arg => undef );

# Pcore::App::HTTP::Controller
# Pcore::App::HTTP::Controller::Index
# Pcore::App::HTTP::Controller::API
# Pcore::App::HTTP::Controller::Static

# TODO die if api controller found, but no api server provided
sub _build_route ($self) {
    my $namespace = ref $self->app;

    my $ns_path = $namespace =~ s[::][/]smgr;

    my $controllers = {};

    # scan namespace, find and preload controllers
    for my $path ( grep { !ref } @INC ) {
        if ( -f "$path/$ns_path.pm" ) {
            $controllers->{ $self->namespace } = '/';
        }

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

                        $controllers->{$class} = '/' . P->text->to_snake_case( $route, delim => '-', split => '/', join => '/' ) . '/';
                    }

                    return;
                }
            );
        }
    }

    for my $class ( sort keys $controllers->%* ) {
        P->class->load($class);

        if ( !$class->does('Pcore::App::HTTP::Controller') ) {
            delete $controllers->{$class};

            say qq["$class" is not a consumer of "Pcore::App::HTTP::Controller"];
        }
        else {
            if ( $class->does('Pcore::App::HTTP::Controller::Index') ) {

                # index controller
            }
            elsif ( $class->does('Pcore::App::HTTP::Controller::Static') ) {

                # static controller
            }
            elsif ( $class->does('Pcore::App::HTTP::Controller::API') ) {

                # api controller
            }
        }
    }

    die qq[Index controller "$namespace" was not found] if !exists $controllers->{$namespace};

    return { reverse $controllers->%* };
}

sub run ( $self, $env ) {
    my $path = P->path( '/' . $env->{PATH_INFO} );

    my $path_tail = $path->filename;

    $path = $path->dirname;

    my $class;

    if ( exists $self->{route}->{$path} ) {
        $class = $self->{route}->{$path};
    }
    else {
        my @labels = split /\//sm, $path;

        while (@labels) {
            $path_tail = pop(@labels) . "/$path_tail";

            $path = join( '/', @labels ) . '/';

            if ( exists $self->{route}->{$path} ) {
                $class = $self->{route}->{$path};

                last;
            }
        }
    }

    my $controller = bless {
        env       => $env,
        router    => $self,
        path      => $path,
        path_tail => P->path($path_tail),
    }, $class;

    return $controller->run;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 52, 78               | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 27, 43, 82, 99       | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::HTTP::Router

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
