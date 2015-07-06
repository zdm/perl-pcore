package Pcore::App::PSGI::Role;

use Pcore qw[-role];

package Pcore::App::PSGI;

use Pcore qw[-cli -class];
use Term::ANSIColor qw[:constants];
use Plack::Builder qw[];
use Pcore::AppX::HasAppX;

extends qw[Pcore::App];

with qw[Pcore::App::PSGI::Role Pcore::App::PSGI::Server];

has env => ( is => 'rw', isa => HashRef, init_arg => undef );

has runtime_cfg      => ( is => 'lazy', isa => HashRef, init_arg => undef );
has runtime_cfg_path => ( is => 'lazy', isa => Str,     init_arg => undef );

# APPX
has_appx router => ( isa => '+Pcore::PSGI::Router' );
has_appx req    => ( isa => '+Pcore::PSGI::Request' );
has_appx tmpl   => ( isa => 'Tmpl', lazy => 0 );

our $CFG = {
    PSGI => {
        SERVER => {
            name         => q[],         # NGINX server_name
            listen       => [':5000'],
            max_requests => 1000,        # 0 - unlimited
            backlog      => 1024
        },
        MIDDLEWARE => [],
    }
};

sub _app {
    my $self = shift;

    my $builder = Plack::Builder->new;

    # apply top-level request-manager middleware
    $builder->add_middleware(
        sub {
            my $app = shift;

            sub {
                my $env = shift;

                # throw APP::REQ::START event
                $self->ev->throw('APP::REQ::START');

                my $res = try {
                    return $app->($env);
                }
                catch {
                    my $e = shift;

                    $e->send_log;

                    return [500];    # return 500 - Interenal Server Error
                };

                # finalize request
                $self->_finalize_req;

                # throw APP::REQ::FINISH event
                $self->ev->throw('APP::REQ::FINISH');

                # print access log to STDERR in devel environment
                if ( $self->env_is_devel ) {

                    # determine content length
                    my $content_length = 0;
                    if ( defined $res->[2] ) {
                        if ( ref $res->[2] eq 'ARRAY' ) {
                            for ( @{ $res->[2] } ) {
                                $content_length += length;
                            }
                        }
                        elsif ( P->scalar->is_glob( $res->[2] ) ) {
                            $content_length = ( -s $res->[2] ) - tell $res->[2];
                        }
                        else {
                            $content_length = q[-];
                        }
                    }

                    my $color = $res->[0] >= 500 ? RED : $res->[0] >= 400 ? BOLD RED : $res->[0] >= 300 ? BOLD YELLOW : q[];

                    say {$STDERR} $color, qq["$env->{REQUEST_METHOD} $env->{REQUEST_URI}" - [$res->[0]] - [$content_length]], RESET;
                }

                return $res;
            };
        }
    );

    # apply middlewares from config
    for my $middleware ( @{ $self->cfg->{PSGI}->{MIDDLEWARE} } ) {
        if ( ref $middleware eq 'ARRAY' ) {
            $builder->add_middleware( @{$middleware} );
        }
        else {
            $builder->add_middleware($middleware);
        }
    }

    # return PSGI response or propagate exception
    my $app = sub {
        my $env = shift;

        $self->env($env);

        # execute request and serialize response to PSGI
        return $self->router->call( $self->req->path )->to_psgi(
            secret            => $self->cfg->{SECRET},
            remote_addr       => $self->req->remote_addr,
            x_accel_locations => $self->req->x_accel_support ? $self->runtime_cfg->{x_accel_locations} : {},
            psgix_body_scalar_refs => $self->env->{'psgix.body.scalar_refs'} // 0,
        );
    };

    P->class->set_subname( __PACKAGE__ . '::app' => $app );

    return $builder->wrap($app);
}

sub _finalize_req {
    my $self = shift;

    # finalize request
    $self->app_reset;

    return;
}

# APP
around _build_cfg => sub {
    my $orig = shift;
    my $self = shift;

    return P->hash->merge( $self->$orig, $CFG );
};

around _create_local_cfg => sub {
    my $orig = shift;
    my $self = shift;

    my $local_cfg = {
        PSGI => {    #
            SERVER => $self->cfg->{PSGI}->{SERVER},
        }
    };

    return P->hash->merge( $self->$orig, $local_cfg );
};

around app_run => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig;

    # preload router, in dev mode routes always builded at server startup, in prod mode - always loaded from local config
    $self->router->app_run;

    if ( $self->is_plackup ) {    # if we run from plackup, NOTE default settings for server not used in this case
        return $self->_app;
    }
    else {
        return $self->runner->run( $self->_app );
    }
};

around app_deploy => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig;

    # build nginx config
    $self->_deploy_nginx_cfg;

    return;
};

# BUILD NGINX CFG
sub _deploy_nginx_cfg {
    my $self = shift;

    $self->_appx_report_info(q[Generate PSGI nginx config']);

    $self->router->app_run;

    my $t = P->tmpl->new( type => 'text' );

    my $params = {
        app_name          => $self->name,
        app_dir           => $self->app_dir,
        resources_dir     => P->res->dist_dir . 'share/',
        log_dir           => $PROC->{LOG_DIR},
        use_ssl           => 0,                                      # TODO
        server_name       => $self->cfg->{PSGI}->{SERVER}->{name},
        ctrl_tmpl         => [],
        x_accel_locations => {},
    };

    # build ctrls nginx configs
    for my $path ( sort keys $self->router->routes->%* ) {
        my $class = $self->router->routes->{$path};

        my $ctrl = P->class->load($class)->new( { app => $self, path => P->file->path( q[], base => $path ) } );

        if ( $ctrl->does('Pcore::PSGI::Controller') ) {
            $self->_appx_report_info(qq[    Found PSGI controller "$class"]);

            if ( my $res = $ctrl->_build_nginx_cfg ) {
                push $params->{ctrl_tmpl}->@*, qq[# $class\n${$res}];
            }

            # collect x_accel_locations
            P->hash->merge( $params->{x_accel_locations}, $ctrl->x_accel_locations );
        }
        else {
            $self->_appx_report_fatal(q[PSGI controller must implement role: "Pcore::PSGI::Controller"]);
        }
    }

    # store x_accel_locations into run-time cfg
    $self->runtime_cfg->{x_accel_locations} = $params->{x_accel_locations};

    $self->store_runtime_cfg;

    my $nginx_cfg_path = $self->app_dir . $self->name . '.nginx';

    $self->_appx_report_info( q[Store PSGI nginx config to '] . $nginx_cfg_path . q['] );

    P->file->write_text( $nginx_cfg_path, $t->render( q[nginx/vhost.nginx], $params ) );

    $self->_appx_report_warn(q[You need to manually copy generated nginx config to nginx app vhosts dir and reload nginx service]);

    return;
}

# RUN-TIME CFG
sub _build_runtime_cfg_path {
    my $self = shift;

    return $self->app_dir . $self->name . '-runtime.cbor';
}

sub _build_runtime_cfg {
    my $self = shift;

    if ( -e $self->runtime_cfg_path ) {
        return P->cfg->load( $self->runtime_cfg_path );
    }
    else {
        return {};
    }
}

sub store_runtime_cfg {
    my $self = shift;

    P->cfg->store( $self->runtime_cfg_path, $self->runtime_cfg, readable => 0 );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 211                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 OPTIONS

=over

=item -l [=] <listen>... | --listen [=] <listen>...

Listens on one or more addresses, whether "HOST:PORT", ":PORT", or "unix://<path>". You may use this option multiple times to listen on multiple addresses, but the server will decide whether it supports multiple interfaces. Default is ":5000".

=item -s [=] <server> | --server [=] <server>

Allowed servers: "Starman", "Feersum", "Thrall". Defaults: "Feersum".

Feersum is recommended to run behind nginx.

=for Euclid:
    server.type: /Starman|Feersum|Thrall|Twiggy.*|Starlet|Monoceros/

=item --workers [=] [<workers>]

Specify a number of preforked workers processes. Preferred value is current number of CPU cores. If value isn't specified - number of cores detected automatically.

=for Euclid:
    workers.type: +int

=item --max-requests [=] <max-requests>

Specify a number of maximum requests per worker, after that worker restart. 0 - means unlimited requests.

=for Euclid:
    max-requests.type: 0+int

=back

=cut
