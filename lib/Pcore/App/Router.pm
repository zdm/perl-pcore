package Pcore::App::Router;

use Pcore -class;

use overload    #
  q[&{}] => sub ( $self, @ ) {
    return sub { return $self->run(@_) };
  },
  fallback => undef;

has app   => ( required => 1 );    # ConsumerOf ['Pcore::App']
has hosts => ( required => 1 );    # HashRef

has map           => ();           # HashRef, router path -> class name
has host_api_path => ();           # HashRef

has _path_class_cache     => ();   # HashRef, router path -> sigleton cache
has _class_instance_cache => ();   # HashRef, class name -> sigleton cache

sub BUILD ( $self, $args ) {

    # init hosts
    $self->{hosts} //= {};

    # add default router
    $self->{hosts}->{'*'} = ref $self->{app} if !keys $self->{hosts}->%*;

    return;
}

sub init ($self) {
    my $map;

    for my $host ( keys $self->{hosts}->%* ) {
        my $ns = $self->{hosts}->{$host} // ref $self->{app};

        $map->{$host} = $self->_get_host_map( $host, $ns );
    }

    $self->{map} = $map;

    return;
}

sub _get_host_map ( $self, $host, $ns ) {
    my $index_class = "${ns}::Index";

    my $index_path = $index_class =~ s[::][/]smgr;

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
        elsif ( index( $module, "$index_path/" ) == 0 ) {
            $modules->{$module} = undef;
        }
    }

    # scan filesystem, find and preload controllers
    for my $path ( grep { !ref } @INC ) {

        # index controller
        if ( -f "$path/$index_module" ) {
            $modules->{$index_module} = undef;
        }

        for my $file ( ( P->path("$path/$index_path")->read_dir( max_depth => 0, is_dir => 0 ) // [] )->@* ) {
            $modules->{"$index_path/$file"} = undef if $file =~ /[.]pm\z/sm;
        }
    }

    my $map;

    for my $module ( sort keys $modules->%* ) {
        my $class = P->class->load($module);

        die qq["$class" is not a consumer of "Pcore::App::Controller"] if !$class->can('does') || !$class->does('Pcore::App::Controller');

        my $obj = $class->new( {
            app  => $self->{app},
            host => $host,
        } );

        my $route;

        # get obj route
        if ( defined $obj->{path} ) {
            $route = $obj->{path};
        }
        else {

            # generate route path
            $route = lc( $class =~ s[\A$index_class:*][/]smr );

            $route =~ s[::][/]smg;

            $obj->{path} = $route;
        }

        die qq[Route "$route" is not unique] if exists $self->{_path_class_cache}->{$host}->{$route};

        $map->{$route} = $class;

        $self->{_class_instance_cache}->{$class} = $self->{_path_class_cache}->{$host}->{$route} = $obj;

        if ( $class->does('Pcore::App::Controller::API') ) {

            # api controller
            $self->{host_api_path}->{$host} = $obj->{path};
        }
    }

    # check, that index controller is present
    if ( !exists $map->{'/'} ) {
        die qq[HTTP router path "/" is required but not found for host "$host"];
    }

    return $map;
}

sub run ( $self, $req ) {
    my $env = $req->{env};

    my $map = $self->{map};

    my $host = $env->{HTTP_HOST} // '*';

    if ( !exists $map->{$host} ) {

        # use default host, if possible
        if ( exists $map->{'*'} ) {
            $host = '*';
        }

        # unknown HTTP host
        else {
            $req->return_xxx(421);    # 421 - misdirected request

            return;
        }
    }

    $map = $map->{$host};

    my $path   = P->path("/$env->{PATH_INFO}");
    my $is_dir = $path ne '/' && !defined $path->{filename};

    my ( $req_path, $class );

    if ( exists $map->{$path} ) {
        $class = $map->{$path};

        $req_path = P->path() if $is_dir;
    }
    else {
        my @labels = split m[/]sm, $path;

        shift @labels;

        my $prefix;

        while () {
            pop @labels;

            $prefix = '/' . join '/', @labels;

            $class = $map->{$prefix};

            last if defined $class;
        }

        if ( $prefix eq '/' ) {
            $req_path = substr $path, length $prefix;
        }
        else {
            $req_path = substr $path, 1 + length $prefix;
        }

        $req_path = P->path( $is_dir ? "$req_path/" : $req_path );
    }

    # extend HTTP request
    $req->{app}  = $self->{app};
    $req->{host} = $host;
    $req->{path} = $req_path;

    my $ctrl = $self->{_class_instance_cache}->{$class};

    Coro::async_pool { $ctrl->run($req) };

    return;
}

sub get_ctrl_by_class_name ( $self, $class_name ) {
    return $self->{_class_instance_cache}->{$class_name};
}

sub get_host_api_path ( $self, $host ) {
    return if !$self->{host_api_path};

    return $self->{host_api_path}->{$host};
}

1;
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
