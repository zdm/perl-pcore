package Pcore::App::HTTP::Router;

use Pcore -class;

with qw[Pcore::HTTP::Server::Router];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App::HTTP'], required => 1 );

has route       => ( is => 'lazy', isa => HashRef, init_arg => undef );
has index_class => ( is => 'ro',   isa => Str,     init_arg => undef );
has api_class   => ( is => 'ro',   isa => Str,     init_arg => undef );

sub _build_route ($self) {
    my $index_class = ref( $self->app ) . '::Index';

    my $controllers = {};

    my $ns_path = $index_class =~ s[::][/]smgr;

    # scan namespace, find and preload controllers
    for my $path ( grep { !ref } @INC ) {
        if ( -f "$path/$ns_path.pm" ) {
            $controllers->{$index_class} = '/';
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
            die qq["$class" is not a consumer of "Pcore::App::HTTP::Controller"];
        }
        else {
            if ( $class->does('Pcore::App::HTTP::Controller::Index') ) {

                # index controller
                $self->{index_class} = $class;
            }
            elsif ( $class->does('Pcore::App::HTTP::Controller::API') ) {

                # api controller
                $self->{api_class} = $class;
            }
        }
    }

    die qq[Index controller "$index_class" was not found or nor a consumer of "Pcore::App::HTTP::Controller::Index"] if !$self->{index_class};

    return { reverse $controllers->%* };
}

sub run ( $self, $req ) {
    my $env = $req->{env};

    my $path = P->path( '/' . $env->{PATH_INFO} );

    my $path_tail = $path->filename;

    $path = $path->dirname;

    my $route = $self->route;

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

    my $controller = $class->new(
        {   app       => $self->{app},
            req       => $req,
            path      => $path,
            path_tail => P->path($path_tail),
        }
    );

    $controller->run;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 48, 70               | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 23, 39, 76, 95       | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
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
