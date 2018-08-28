package Pcore::App;

use Pcore -role;
use Pcore::Nginx;
use Pcore::HTTP::Server;
use Pcore::App::Router;
use Pcore::App::API;

has app_cfg => ( required => 1 );    # HashRef
has devel => 0;                      # Bool

has server => ( init_arg => undef ); # InstanceOf ['Pcore::HTTP::Server']
has router => ( init_arg => undef ); # InstanceOf ['Pcore::App::Router']
has api    => ( init_arg => undef ); # Maybe [ ConsumerOf ['Pcore::App::API'] ]
has node   => ( init_arg => undef ); # InstanceOf ['Pcore::Node']

sub BUILD ( $self, $args ) {

    # apply default HTTP router settings
    $self->{app_cfg}->{router} //= { '*' => ref $self };

    # create HTTP router
    $self->{router} = Pcore::App::Router->new( {
        app   => $self,
        hosts => $self->{app_cfg}->{router},
    } );

    # create API object
    $self->{api} = Pcore::App::API->new($self);

    return;
}

sub get_default_locale ( $self, $req ) {
    return 'en';
}

around run => sub ( $orig, $self ) {

    # create node
    # TODO when to use node???
    if (1) {
        require Pcore::Node;

        my $node_req = ${ ref($self) . '::NODE_REQUIRES' };

        my $requires = defined $node_req ? { $node_req->%* } : {};

        $requires->{'Pcore::App::API::Node'} = undef if $self->{app_cfg}->{api}->{connect};

        $self->{node} = Pcore::Node->new( {
            type     => ref $self,
            requires => $requires,
            server   => do {
                if ( $self->{app_cfg}->{node}->{server}->{connect} ) {
                    $self->{app_cfg}->{node}->{server}->{connect};
                }
                else {
                    Pcore::Node::Server->new( $self->{app_cfg}->{node}->{server} );
                }
            },
            listen   => $self->{app_cfg}->{node}->{listen},
            on_event => do {
                if ( $self->can('NODE_ON_EVENT') ) {
                    sub ( $node, $ev ) {
                        $self->NODE_ON_EVENT($ev);

                        return;
                    };
                }
            },
            on_rpc => do {
                if ( $self->can('NODE_ON_RPC') ) {
                    sub ( $node, $req, $tx ) {
                        $self->NODE_ON_RPC( $req, $tx );

                        return;
                    };
                }
            },
        } );
    }

    # connect api
    my $res = $self->{api}->init;
    say 'API initialization ... ' . $res;
    exit 3 if !$res;

    # scan HTTP controllers
    print 'Scanning HTTP controllers ... ';
    $self->{router}->init;
    say 'done';

    $res = $self->$orig;
    exit 3 if !$res;

    # start HTTP server
    if ( defined $self->{app_cfg}->{server}->{listen} ) {
        $self->{server} = Pcore::HTTP::Server->new( {
            $self->{app_cfg}->{server}->%*,    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]
            on_request => $self->{router}
        } );

        say qq[Listen: $self->{app_cfg}->{server}->{listen}];
    }

    say qq[App "@{[ref $self]}" started];

    return;
};

sub api_call ( $self, @args ) {
    my $auth = bless { app => $self }, 'Pcore::App::API::Auth';

    return $auth->api_call(@args);
}

sub nginx_cfg ($self) {
    my $www_storage = $ENV->{share}->get_storage('www');

    my $params = {
        name              => lc( ref $self ) =~ s/::/-/smgr,
        data_dir          => $ENV->{DATA_DIR},
        www_root_dir      => $www_storage ? $www_storage->[0] : undef,                                   # TODO
        default_server    => 1,                                                                          # generate default server config
        nginx_default_key => $ENV->{share}->get('data/nginx/default.key'),
        nginx_default_pem => $ENV->{share}->get('data/nginx/default.pem'),
        upstream          => P->uri( $self->{app_cfg}->{server}->{listen} )->to_nginx_upstream_server,
    };

    for my $host ( keys $self->{router}->{_path_class_cache}->%* ) {
        my $host_name;

        if ( $host eq '*' ) {
            $params->{default_server} = 0;

            $host_name = q[""];
        }
        else {
            $host_name = $host;
        }

        for my $path ( keys $self->{router}->{_path_class_cache}->{$host}->%* ) {
            my $ctrl = $self->{router}->{_path_class_cache}->{$host}->{$path};

            push $params->{host}->{$host_name}->{location}->@*, $ctrl->get_nginx_cfg;
        }
    }

    return P->tmpl->new->render( $self->{app_cfg}->{server}->{ssl} ? 'nginx/host_conf.nginx' : 'nginx/host_conf_no_ssl.nginx', $params );
}

sub start_nginx ($self) {
    $self->{nginx} = Pcore::Nginx->new;

    $self->{nginx}->add_vhost( 'vhost', $self->nginx_cfg ) if !$self->{nginx}->is_vhost_exists('vhost');

    # SIGNUP -> nginx reload
    $SIG->{HUP} = AE::signal HUP => sub {
        kill 'HUP', $self->{nginx}->proc->pid || 0;

        return;
    };

    $self->{nginx}->run;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App

=head1 SYNOPSIS

    my $app = Test::App->new( {    #
        app_cfg => {
            server => {            # passed directly to the Pcore::HTTP::Server constructor
                listen            => '*:80',    # 'unix:/var/run/test.sock'
                keepalive_timeout => 180,
            },
            router => {                         # passed directly to the Pcore::App::Router
                '*'         => undef,
                'host1.com' => 'Test::App::App1',
                'host2.com' => 'Test::App::App2',
            },
            api => {
                connect => "sqlite:$ENV->{DATA_DIR}auth.sqlite",
                rpc => {
                    workers => undef,           # Maybe[Int]
                    argon   => {
                        argon2_time        => 3,
                        argon2_memory      => '64M',
                        argon2_parallelism => 1,
                    },
                },
            }
        },
        devel => $ENV->cli->{opt}->{devel},
    } );

    $app->run( sub ($res) {
        return;
    } );

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 API METHOD PERMISSSIONS

=over

=item undef

allows to call API method without authentication.

=item "*"

allows any authenticated user.

=item ArrayRef[Str]

array of roles names, that are allowed to run this method.

=back

=head1 SEE ALSO

=cut
