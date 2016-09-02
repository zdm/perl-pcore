package Pcore::App::Router;

use Pcore -class;

with qw[Pcore::HTTP::Server::Router];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has map         => ( is => 'lazy', isa => HashRef, init_arg => undef );
has index_class => ( is => 'ro',   isa => Str,     init_arg => undef );
has api_class   => ( is => 'ro',   isa => Str,     init_arg => undef );

has _cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );    # HTTP controllers cache

sub _perl_class_path_to_snake_case ($str) {

    # convert aB -> a-b
    $str =~ s/([[:lower:]])([[:upper:]])/"$1-" . lc $2/smge;

    # convert Ab -> -ab, if "A" is not first symbol and "A" if not after "/"
    $str =~ s[([^/])([[:upper:]])([[:lower:]])]["$1-" . lc($2) . $3]smge;

    return lc $str;
}

sub _build_map ($self) {
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

                        $controllers->{$class} = '/' . _perl_class_path_to_snake_case($route) . '/';
                    }

                    return;
                }
            );
        }
    }

    for my $class ( sort keys $controllers->%* ) {
        P->class->load($class);

        if ( !$class->does('Pcore::App::Controller') ) {
            die qq["$class" is not a consumer of "Pcore::App::Controller"];
        }
        else {
            if ( $class->does('Pcore::App::Controller::Index') ) {

                # index controller
                $self->{index_class} = $class;
            }
            elsif ( $class->does('Pcore::App::Controller::API') ) {

                # api controller
                $self->{api_class} = $class;
            }
        }
    }

    die qq[Index controller "$index_class" was not found or nor a consumer of "Pcore::App::Controller::Index"] if !$self->{index_class};

    return { reverse $controllers->%* };
}

sub run ( $self, $req ) {
    my $env = $req->{env};

    my $path = P->path( '/' . $env->{PATH_INFO} );

    my $path_tail = $path->filename;

    $path = $path->dirname;

    my $map = $self->map;

    my $class;

    if ( exists $map->{$path} ) {
        $class = $map->{$path};
    }
    else {
        my @labels = split /\//sm, $path;

        while (@labels) {
            $path_tail = pop(@labels) . "/$path_tail";

            $path = join( '/', @labels ) . '/';

            if ( exists $map->{$path} ) {
                $class = $map->{$path};

                last;
            }
        }
    }

    $req->@{qw[path path_tail]} = ( $path, P->path($path_tail) );

    my $ctrl = $self->{_cache}->{$path} //= $class->new(
        {   app  => $self->{app},
            path => $path,
        }
    );

    $ctrl->run($req);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 36, 52, 89, 108      | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Router

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
