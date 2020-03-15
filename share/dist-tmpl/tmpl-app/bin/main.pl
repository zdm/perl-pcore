#!/usr/bin/env perl

package main v0.1.0;

use Pcore -forktmpl;
use <: $module_name :>;
use <: $module_name ~ "::Const qw[]" :>;

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

# load app config
my $cfg = P->cfg->read( "$ENV->{DATA_DIR}/cfg.yaml", params => { DATA_DIR => $ENV->{DATA_DIR} } );

my $app_cfg = {           #
    cfg => {

        # DB
        db => $cfg->{db},

        # SERVER
        server => {
            default => {
                namespace   => undef,
                listen      => undef,
                server_name => [],
            },
        },

        # NODE
        node => {
            server => $cfg->{node}->{server},
            listen => $cfg->{node}->{listen},
        },

        # API
        api => {
            backend => $cfg->{db},
            node    => {
                workers => undef,
                argon   => {
                    argon2_time        => 3,
                    argon2_memory      => '64M',
                    argon2_parallelism => 1,
                },
            },
        },
    },
    devel => $ENV->{cli}->{opt}->{devel},
};

# merge server config
for my $server ( keys $app_cfg->{cfg}->{server}->%* ) {

    # listen
    if ( my $listen = $cfg->{server}->{$server}->{listen} ) {
        $app_cfg->{cfg}->{server}->{$server}->{listen} = $listen;
    }

    # server_name
    if ( my $server_name = $cfg->{server}->{$server}->{server_name} ) {
        push $app_cfg->{cfg}->{server}->{$server}->{server_name}->@*, P->scalar->is_plain_arrayref($server_name) ? $server_name->@* : $server_name;
    }
}

my $app = <: $module_name :>->new($app_cfg);

my $cv = P->cv;

$app->run;

$app->start_nginx;

$cv->recv;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 7                    | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
