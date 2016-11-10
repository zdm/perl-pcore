package Pcore::App::Router;

use Pcore -class;

with qw[Pcore::HTTP::Server::Router];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has map         => ( is => 'lazy', isa => HashRef, init_arg => undef );    # router path -> class name
has index_class => ( is => 'ro',   isa => Str,     init_arg => undef );
has api_class   => ( is => 'ro',   isa => Str,     init_arg => undef );

has _path_class_cache     => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );    # router path -> sigleton cache
has _class_instance_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );    # class name -> sigleton cache

sub _build_map ($self) {
    my $index_class = ref( $self->app ) . '::Index';

    my $index_path = ( $index_class =~ s[::][/]smgr ) . q[/];

    my $index_module = ( $index_class =~ s[::][/]smgr ) . '.pm';

    # related to $index_path module path -> full module path mapping
    my $modules = {};

    # scan %INC
    for my $module ( keys %INC ) {
        next if substr( $module, -3 ) ne '.pm';

        # index controller
        if ( $module eq $index_module ) {
            $modules->{$module} = undef;
        }

        # non-index controller
        elsif ( index( $module, $index_path ) == 0 ) {
            $modules->{$module} = undef;
        }
    }

    # scan filesystem, find and preload controllers
    for my $path ( grep { !ref } @INC ) {

        # index controller
        if ( -f "$path/$index_module" ) {
            $modules->{$index_module} = undef;
        }

        if ( -d "$path/$index_path" ) {
            P->file->find(
                "$path/$index_path",
                abs => 0,
                dir => 0,
                sub ($path) {
                    $modules->{"${index_path}${path}"} = undef if $path->suffix eq 'pm';

                    return;
                }
            );
        }
    }

    my $map;

    for my $module ( sort keys $modules->%* ) {
        my $class = P->class->load($module);

        die qq["$class" is not a consumer of "Pcore::App::Controller"] if !$class->does('Pcore::App::Controller');

        my $obj = $class->new( { app => $self->{app} } );

        my $route = $obj->path;

        # create route automatically
        if ( !$route ) {
            $route = lc( ( $class . '::' ) =~ s[\A$index_class:*][/]smr );

            $route =~ s[::][/]smg;

            $obj->{path} = $route;
        }

        die qq[Route "$route" is not unique] if exists $self->{_path_class_cache}->{$route};

        $map->{$route} = $class;

        $self->{_class_instance_cache}->{$class} = $self->{_path_class_cache}->{$route} = $obj;

        if ( $class->does('Pcore::App::Controller::Index') && $route eq '/' ) {

            # index controller
            $self->{index_class} = $class;
        }
        elsif ( $class->does('Pcore::App::Controller::API') ) {

            # api controller
            $self->{api_class} = $class;
        }
    }

    die qq[Index controller "$index_class" was not found or not a consumer of "Pcore::App::Controller::Index"] if !$self->{index_class};

    return $map;
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

    $self->{_path_class_cache}->{$path}->run($req);

    return;
}

sub get_instance ( $self, $class_name ) {
    return $self->{_class_instance_cache}->{$class_name};
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 76, 89, 109, 128     | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
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
