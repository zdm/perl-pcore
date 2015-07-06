package Pcore::App::Role;

use Pcore qw[-role];

package Pcore::AppX::Role;

use Pcore qw[-role];
use Term::ANSIColor qw[:constants];

has _appx_enum     => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has _appx_builded  => ( is => 'rw',   isa => Bool,     default  => 0 );
has _appx_deployed => ( is => 'rw',   isa => Bool,     default  => 0 );

sub _build__appx_enum {
    my $self = shift;

    my $enum = [];

    for my $attr_name ( sort { $a cmp $b } grep { $Moo::MAKERS{ ref $self }->{constructor}->{attribute_specs}->{$_}->{is_appx} } keys %{ $Moo::MAKERS{ ref $self }->{constructor}->{attribute_specs} } ) {
        push @{$enum}, $Moo::MAKERS{ ref $self }->{constructor}->{attribute_specs}->{$attr_name};
    }

    return $enum;
}

# REPORT
sub _appx_report_fatal {
    my $self = shift;

    say BOLD . RED . q[[ FATAL ] ] . RESET . shift;

    exit 255;
}

sub _appx_report_warn {
    my $self = shift;

    say BOLD . YELLOW . q[[ WARN ]  ] . RESET . shift;

    return;
}

sub _appx_report_info {
    my $self = shift;

    say shift;

    return;
}

# APPX
around app_build => sub {
    my $orig = shift;
    my $self = shift;

    if ( !$self->_appx_builded ) {
        $self->_appx_builded(1);

        for my $attr ( @{ $self->_appx_enum } ) {
            my $attr_reader = $attr->{reader};
            $self->_appx_report_info(qq[Build AppX component "$attr_reader"]);
            $self->$attr_reader->app_build;
        }

        $self->$orig;
    }

    return;
};

around app_deploy => sub {
    my $orig = shift;
    my $self = shift;

    if ( !$self->_appx_deployed ) {
        $self->_appx_deployed(1);

        for my $attr ( @{ $self->_appx_enum } ) {
            my $attr_reader = $attr->{reader};
            $self->_appx_report_info(qq[Deploy AppX component "$attr_reader"]);
            $self->$attr_reader->app_deploy;
        }

        $self->$orig;
    }

    return;
};

around app_reset => sub {
    my $orig = shift;
    my $self = shift;

    # call reset of included AppX objects
    for my $attr ( @{ $self->_appx_enum } ) {
        my $attr_reader = $attr->{reader};
        my $predicate   = $attr->{predicate};

        if ( $self->$predicate ) {    # if attr has value
            if ( $self->$attr_reader->appx_reset eq 'CLEAR' ) {
                my $clearer = $attr->{clearer};
                $self->$clearer;
            }
            else {
                $self->$attr_reader->app_reset;
            }
        }
    }

    $self->$orig;

    return;
};

package Pcore::App;

use Pcore qw[-cli -class];
use Pcore::AppX::HasAppX;

with qw[Pcore::App::Role];
with qw[Pcore::AppX::Role];

has name            => ( is => 'ro',   isa => SnakeCaseStr, required => 1 );
has name_camel_case => ( is => 'lazy', isa => Str,          init_arg => undef );
has ns              => ( is => 'ro',   isa => ClassNameStr, required => 1 );
has cfg             => ( is => 'lazy', isa => HashRef,      init_arg => undef );
has app_dir         => ( is => 'lazy', isa => Str,          init_arg => undef );
has _local_cfg_path => ( is => 'lazy', isa => Str,          init_arg => undef );

# RUN-TIME ENVIRONMENT
has runtime_env => ( is => 'rwp', isa => Enum [qw[development test production]], default => 'production' );
has env_is_devel => ( is => 'lazy', isa => Bool, init_arg => undef );
has env_is_test  => ( is => 'lazy', isa => Bool, init_arg => undef );
has env_is_prod  => ( is => 'lazy', isa => Bool, init_arg => undef );

# APPX
has_appx ev      => ( isa => 'EV' );
has_appx openssl => ( isa => 'OpenSSL' );
has_appx h       => ( isa => 'H' );
has_appx api     => ( isa => 'API' );

our $CFG = { SECRET => undef, };

sub BUILD {
    my $self = shift;
    my $args = shift;

    P->hash->merge( $self->cfg, $args->{cfg} ) if $args->{cfg};    # merge default cfg with inline cfg
    P->hash->merge( $self->cfg, $self->_read_local_cfg );          # merge with local cfg

    return;
}

# CFG
sub _build_name_camel_case {
    my $self = shift;

    return P->text->to_camel_case( $self->name, ucfirst => 1 );
}

sub _build_app_dir {
    my $self = shift;

    my $dir = $PROC->{DATA_DIR} . $self->name . q[/];
    P->file->mkpath($dir);

    return $dir;
}

sub _build_cfg {
    my $self = shift;

    return $CFG;    # return default cfg
}

sub _build__local_cfg_path {
    my $self = shift;

    return $self->app_dir . $self->name . q[.perl];
}

sub _read_local_cfg {
    my $self = shift;

    return -f $self->_local_cfg_path ? P->cfg->load( $self->_local_cfg_path ) : {};
}

sub _create_local_cfg {
    my $self = shift;

    # create local cfg
    my $local_cfg = { SECRET => P->random->bytes_hex(16), };

    # create AppX local configs
    for my $attr ( @{ $self->_appx_enum } ) {
        my $attr_reader = $attr->{reader};
        $self->$attr_reader->_create_local_cfg($local_cfg);
    }

    # cluster specified in command line
    # if ( $ARGV{app_deploy} ) {
    #     $local_cfg->{CLUSTER}->{USE_CLUSTER} = 1;
    #     $local_cfg->{CLUSTER}->{host}        = $ARGV{app_deploy};
    # }

    return $local_cfg;
}

# RUN-TIME ENVIRONMENT
sub _build_env_is_devel {
    my $self = shift;

    return $self->runtime_env eq 'development' ? 1 : 0;
}

sub _build_env_is_test {
    my $self = shift;

    return $self->runtime_env eq 'test' ? 1 : 0;
}

sub _build_env_is_prod {
    my $self = shift;

    return $self->runtime_env eq 'production' ? 1 : 0;
}

# PHASES
sub run {
    my $self = shift;

    # process -E option
    if ( $ARGV{env} ) {
        $self->_set_runtime_env('development') if $ARGV{env} =~ /\Adev/sm;
        $self->_set_runtime_env('test')        if $ARGV{env} =~ /\Atest/sm;
        $self->_set_runtime_env('production')  if $ARGV{env} =~ /\Aprod/sm;
    }

    if ( $ARGV{app} ) {
        if ( $ARGV{app} eq 'build' ) {
            $self->_appx_report_info( q[Build application "] . $self->name . q["] );
            $self->_appx_report_info( q[Application data dir "] . $self->app_dir . q["] );

            $self->app_build;

            $self->_appx_report_info(q[Build completed]);

            exit;
        }
        elsif ( $ARGV{app} eq 'deploy' ) {
            $self->_appx_report_info( q[Deploy application "] . $self->name . q["] );
            $self->_appx_report_info( q[Application data dir "] . $self->app_dir . q["] );

            $self->app_deploy;

            $self->_appx_report_info(q[Deploy completed]);

            exit;
        }
        elsif ( $ARGV{app} eq 'test' ) {
            $self->_appx_report_info( q[Test application "] . $self->name . q["] );
            $self->_appx_report_info( q[Application data dir "] . $self->app_dir . q["] );

            $self->app_test;

            $self->_appx_report_info(q[Test completed]);

            exit;
        }
    }

    return $self->app_run;
}

sub app_build {
    my $self = shift;

    # create local cfg
    $self->_appx_report_info(q[Create local config]);
    my $local_cfg = $self->_create_local_cfg;
    P->hash->merge( $local_cfg, $self->_read_local_cfg );    # override local cfg with already configured values

    # store local config
    $self->_appx_report_info( q[Store local config to "] . $self->_local_cfg_path . q["] );
    P->cfg->store( $self->_local_cfg_path, $local_cfg, readable => 1 );

    return;
}

sub app_deploy {
    my $self = shift;

    return;
}

sub app_test {
    my $self = shift;

    return;
}

sub app_run {
    my $self = shift;

    # create handles
    $self->h->app_run;

    # preload API
    $self->api->app_run;

    return;
}

sub app_reset {
    my $self = shift;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 27                   │ * Private subroutine/method '_appx_report_fatal' declared but not used                                         │
## │      │ 35                   │ * Private subroutine/method '_appx_report_warn' declared but not used                                          │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 OPTIONS

=over

=item -E [=] [<env>] | --env [=] [<env>]

Available values: "prod[uction]", "dev[elopment]", "test". If option is present, but <env> isn't specified - "development" value will be used.

=for Euclid:
    env.type: /prod.*|dev.*|test/
    env.default: 'production'
    env.opt_default: 'development'

=item --app [=] <command>

Application related commands:

    build  - build application
    deploy - deploy application
    test   - test application

=for Euclid:
    command.type: /(build|deploy|test)/

=back

=cut
