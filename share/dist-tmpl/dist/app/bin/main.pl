#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Pcore::Nginx;
use <: $module_name :>;
use <: $module_name :> ::Const qw[:CONST];

sub CLI {
    return {
        opt => {
            devel => {    #
                desc    => 'Run in development mode.',
                default => 0,
            },
        },
    };
}

my $cfg = P->cfg->load("$ENV->{DATA_DIR}cfg.ini");

my $app = <: $module_name :>->new( {    #
    app_cfg => {
        server => {                     # passed directly to the Pcore::HTTP::Server constructor
            listen => 'unix:/var/run/<: $dist_path :>.sock',
        },
        api => {

            # connect => $cfg->{_}->{auth},
            rpc => {
                workers => undef,
                argon   => {
                    argon2_time        => 3,
                    argon2_memory      => '64M',
                    argon2_parallelism => 1,
                },
            },
        }
    },
    devel => $ENV->cli->{opt}->{devel},
    cfg   => $cfg,
} );

my $cv = AE::cv;

$app->run( sub ($app) {
    _start_nginx();

    return;
} );

$cv->recv;

sub _start_nginx {
    our $NGINX = Pcore::Nginx->new;

    $NGINX->add_vhost( '<: $dist_path :>', P->file->read_bin( $ENV->dist->root . 'contrib/conf.nginx' ) ) if !$NGINX->is_vhost_exists('<: $dist_path :>');

    # SIGNUP -> nginx reload
    $SIG->{HUP} = AE::signal HUP => sub {
        kill 'HUP', $NGINX->proc->pid || 0;

        return;
    };

    $NGINX->run;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    1 | 26, 58               | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
