package Pcore::PSGI::Controller::ExtJS;

use Pcore qw[-role];

with qw[Pcore::PSGI::Controller];

requires qw[_build_ext_app_name];

has ext_app_name => ( is => 'lazy', isa => SnakeCaseStr );
has title        => ( is => 'lazy', isa => Str );
has ext_theme    => ( is => 'lazy', isa => Enum [qw[classic classic-sandbox crisp crisp-touch gray neptune neptune-touch aria]] );
has ext_locale   => ( is => 'lazy', isa => Str );

has ext_app_name_camel_case => ( is => 'lazy', isa => Str, init_arg => undef );
has ext_app_ns              => ( is => 'lazy', isa => Str, init_arg => undef );
has ext_class_ns            => ( is => 'lazy', isa => Str, init_arg => undef );
has ext_class_name          => ( is => 'lazy', isa => Str, init_arg => undef );

has ext_app_full_name => ( is => 'lazy', isa => Str, init_arg => undef );

our $DEFAULT_API = {
    type                 => 'remoting',
    namespace            => undef,
    disableNestedActions => $FALSE,
    maxRetries           => 0,
    timeout              => 5000,         # timeout to use for each request (milliseconds)
    enableBuffer         => 10            # buffer waiting time in millisecs
};

no Pcore;

sub _build_ext_app_name_camel_case {
    my $self = shift;

    return P->text->to_camel_case( $self->ext_app_name, ucfirst => 1 );
}

sub _build_ext_app_ns {
    my $self = shift;

    return $self->app->name_camel_case . $self->ext_app_name_camel_case;
}

sub _build_title {
    my $self = shift;

    return $self->app->name_camel_case;
}

sub _build_ext_theme {
    my $self = shift;

    return 'crisp';
}

sub _build_ext_locale {
    my $self = shift;

    return 'en';
}

sub run {
    my $self = shift;

    return $self->req->set_status(405) unless $self->req->is_get;

    # require authentication
    if ( !$self->api->is_authenticated ) {
        return $self->res->set_status(307)->add_headers( LOCATION => '/api/signin/?continue=' . P->data->to_uri( $self->req->env->{REQUEST_URI} ) );
    }

    if ( !$self->path || $self->path eq 'index.html' ) {
        my $ext_theme  = $self->ext_theme;
        my $ext_locale = $self->ext_locale;

        my $loader_path = {
            q[*]                                => q[.],
            Pcore                               => '/static/sencha/ext/pcore',
            Ext                                 => '/static/sencha/ext/src',
            'Ext.ux'                            => '/static/sencha/ext/ux',
            $self->ext_app_ns                   => q[.],
            $self->app->name_camel_case . 'Api' => '/api',
        };

        my $resources = {
            INDEX => { title => $self->title, },
            ext   => {
                loader_path    => P->text->mark_raw( P->data->to_json( $loader_path,        readable => $self->app->env_is_devel )->$* ),
                app_ns         => $self->ext_app_ns,
                api_map        => P->text->mark_raw( P->data->to_json( $self->_get_api_map, readable => $self->app->env_is_devel )->$* ),
                viewport_class => $self->ext_app_ns . '.Viewport',
                locale         => $ext_locale,
            },
            devel => $self->app->env_is_devel,
        };

        if ( $self->app->env_is_devel ) {
            $resources->{ext}->{extjs}     = '/static/sencha/ext/build/ext-all-debug.js';
            $resources->{ext}->{theme_css} = qq[/static/sencha/ext/build/packages/ext-theme-$ext_theme/build/resources/ext-theme-$ext_theme-all-debug.css];
            $resources->{ext}->{theme_js}  = qq[/static/sencha/ext/build/packages/ext-theme-$ext_theme/build/ext-theme-$ext_theme-debug.js];
            $resources->{ext}->{locale_js} = qq[/static/sencha/ext/build/packages/ext-locale/build/ext-locale-$ext_locale-debug.js];
        }
        else {
            $resources->{ext}->{extjs}     = '/static/sencha/ext/build/ext-all.js';
            $resources->{ext}->{theme_css} = qq[/static/sencha/ext/build/packages/ext-theme-$ext_theme/build/resources/ext-theme-$ext_theme-all.css];
            $resources->{ext}->{theme_js}  = qq[/static/sencha/ext/build/packages/ext-theme-$ext_theme/build/ext-theme-$ext_theme.js];
            $resources->{ext}->{locale_js} = qq[/static/sencha/ext/build/packages/ext-locale/build/ext-locale-$ext_locale.js];
        }

        return $self->render( 'sencha/index-extjs.html', $resources );
    }
    else {
        return $self->ext_class_generator;
    }
}

sub _get_api_map {
    my $self = shift;

    my $api_map = P->hash->merge( $DEFAULT_API, $self->api->get_api_map );

    $api_map->{namespace} = $self->app->name;

    return $api_map;
}

# CLASS GENERATION METHODS
sub ext_class_generator {
    my $self = shift;

    my $perl_class = $self->app->ns . q[::Ext::] . $self->ext_app_name_camel_case;

    $perl_class .= q[::] . P->text->to_camel_case( $self->ext_class_ns, ucfirst => 1, split => q[.], join => q[::] ) if $self->ext_class_ns;

    my $is_success = try {
        return P->class->load( $perl_class, does => 'Pcore::JS::ExtJS::Namespace' );
    }
    catch {
        my $e = shift;

        $e->send_log;

        return;
    };

    return $self->res->set_status(404) unless $is_success;

    my $namespace_obj = $perl_class->new(
        {   app_name       => $self->app->name,
            ext_app_name   => $self->ext_app_name,
            ext_class_ns   => $self->ext_class_ns,
            ext_class_name => $self->ext_class_name,
        }
    );

    my $js = $namespace_obj->ext_generate_class( readable => $self->app->env_is_devel );

    if ($js) {
        my $res = $self->res($js)->set_headers( CONTENT_TYPE => 'application/javascript' );
        $res->set_no_cache;

        return $res;
    }
    else {
        return $self->res->set_status(404);
    }
}

sub _build_ext_class_ns {
    my $self = shift;

    my $ext_class_ns = lc $self->path->dirname;

    $ext_class_ns =~ s[/\z][]sm;
    $ext_class_ns =~ s[/][.]smg;

    return $ext_class_ns;
}

sub _build_ext_class_name {
    my $self = shift;

    return $self->path->filename_base;
}

1;
__END__
=pod

=encoding utf8

=cut
