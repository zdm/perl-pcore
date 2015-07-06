package Pcore::PSGI::Router;

use Pcore qw[-class];
use Pcore::Util::UA::Response;

with qw[Pcore::AppX];

has _base_ns => ( is => 'lazy', isa => Str, init_arg => undef );
has _ua => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::UA'], init_arg => undef );
has _cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

# APPX
sub app_build {
    my $self = shift;

    $self->_appx_report_info( q[Indexing PSGI controllers in '] . $self->app->ns . q[::Controller::' namespace] );

    # create default path (/)
    my $routes = { q[/] => $self->_base_ns . 'Index' };

    my $sub = sub {
        my %args = @_;

        $self->_appx_report_info(qq[    Found PSGI controller '$args{class}']);

        P->class->load( $args{class} );
        if ( $args{class}->does('Pcore::PSGI::Controller') ) {
            $routes->{ $args{path} } = $args{class};
        }
        else {
            $self->_appx_report_fatal(q[PSGI controller must implement role: 'Pcore::PSGI::Controller']);
        }

        return;
    };

    $self->_find_ctrls($sub);

    $self->app->runtime_cfg->{routes} = $routes;
    $self->app->store_runtime_cfg;

    $self->_cache->{routes} = $routes;

    return;
}

sub app_run {
    my $self = shift;

    if ( $self->app->env_is_prod ) {
        if ( exists $self->app->runtime_cfg->{routes} ) {
            $self->_cache->{routes} = $self->app->runtime_cfg->{routes};
        }
        else {
            die q[Router config wasn't found. Build app first];
        }
    }
    else {    # in devel environment always build routes during startup
        $self->app_build;
    }

    $self->_cache->{ctrl} = { reverse %{ $self->_cache->{routes} } };

    return;
}

# LOAD OR BUILD ROUTES
sub _find_ctrls {
    my $self = shift;
    my $cb   = shift;

    # index controllers classes, create routes
    my $ns_class = $self->_base_ns . q[Controller::];
    my $ns_path  = $ns_class =~ s[::][/]smgr;

    for my $path ( grep { -d qq[$_/$ns_path] } @INC ) {
        P->file->finddepth(
            {   wanted => sub {
                    my $filename = $_;
                    if ( $filename =~ /[.]pm\z/sm ) {
                        $filename =~ s[\A$path/$ns_path][]sm;
                        $filename =~ s/[.]pm\z//sm;
                        $cb->( path => q[/] . lc $filename . q[/], class => $ns_class . $filename =~ s[/][::]smgr );
                    }
                },
                no_chdir => 1
            },
            $path . q[/] . $ns_path
        );
    }

    return;
}

sub _build__ua {
    my $self = shift;

    return P->ua->new;
}

sub _build__base_ns {
    my $self = shift;

    return $self->app->ns . q[::];
}

sub routes {
    my $self = shift;

    return $self->_cache->{routes};
}

# for external calls use: http[s]://url, method, @UA params
sub call {
    my $self = shift;
    my $path = shift;
    my @args = @_;

    my $res;

    if ( $path =~ /\Ahttp/sm ) {
        my $method = shift // 'GET';

        $res = $self->_ua->request( $method, $path, @args );
    }
    else {    # path MUST be the absolute controller path as string

        # parse inline method: /api/ctrl/#get, API::Controller#get
        ( $path, my $method ) = split /#/sm, $path;

        # "run" is the default method if other isn't defined
        $method ||= 'run';

        if ( my $class = $self->path_to_ctrl($path) ) {
            my $ctrl = P->class->load($class)->new( { app => $self->app, path => P->file->path( $path, base => $self->ctrl_to_path($class) ) } );

            $res = Pcore::Util::UA::Response->new_response( $ctrl->$method(@args) );
        }
        else {
            $res = Pcore::Util::UA::Response->new->set_status(404);
        }
    }

    return $res;
}

sub path_to_ctrl {
    my $self = shift;
    my $path = shift;

    my $normalized_path = $path =~ s[/[^/]+\z][/]smr;

    if ( $self->_cache->{routes_path}->{$normalized_path} ) {
        return $self->_cache->{routes_path}->{$normalized_path};
    }
    else {
        my $max_path = q[];    # matched path is a maximum matched path

        for my $route ( keys %{ $self->routes } ) {
            $max_path = $route if ( index $normalized_path, $route, 0 ) == 0 && length $max_path < length $route;
        }

        if ($max_path) {
            my $ctrl = $self->routes->{$max_path};
            if ( $ctrl =~ m[/]sm ) {
                $self->_cache->{routes_path}->{$normalized_path} = __SUB__->( $self, $ctrl );
            }
            else {
                $self->_cache->{routes_path}->{$normalized_path} = $ctrl;
            }

            return $self->_cache->{routes_path}->{$normalized_path};
        }
        else {
            die qq[Invalid controller path "$path"];
        }
    }
}

sub ctrl_to_path {
    my $self = shift;
    my $ctrl = shift;

    return $self->_cache->{ctrl}->{$ctrl};
}

sub is_exists {
    my $self = shift;
    my $path = shift;

    return $self->path_to_ctrl($path) ? 1 : 0;
}

1;
__END__
=pod

=encoding utf8

=cut
