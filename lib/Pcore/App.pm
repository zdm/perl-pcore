package Pcore::App::Role;

use Pcore -role;

package Pcore::AppX::Role;

use Pcore -role, -ansi;

has _appx_enum     => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has _appx_builded  => ( is => 'rw',   isa => Bool,     default  => 0 );
has _appx_deployed => ( is => 'rw',   isa => Bool,     default  => 0 );

sub _build__appx_enum ($self) {
    my $enum = [];

    for my $attr_name ( sort { $a cmp $b } grep { $Moo::MAKERS{ ref $self }->{constructor}->{attribute_specs}->{$_}->{is_appx} } keys $Moo::MAKERS{ ref $self }->{constructor}->{attribute_specs}->%* ) {
        push $enum->@*, $Moo::MAKERS{ ref $self }->{constructor}->{attribute_specs}->{$attr_name};
    }

    return $enum;
}

# REPORT
sub _appx_report_fatal ( $self, $msg ) {
    say BOLD . RED . q[[ FATAL ] ] . RESET . $msg;

    exit 255;
}

sub _appx_report_warn ( $self, $msg ) {
    say BOLD . YELLOW . q[[ WARN ]  ] . RESET . $msg;

    return;
}

sub _appx_report_info ( $self, $msg ) {
    say $msg;

    return;
}

# APPX
around app_build => sub ( $orig, $self ) {
    if ( !$self->_appx_builded ) {
        $self->_appx_builded(1);

        for my $attr ( $self->_appx_enum->@* ) {
            my $attr_reader = $attr->{reader};

            $self->_appx_report_info(qq[Build AppX component "$attr_reader"]);

            $self->$attr_reader->app_build;
        }

        $self->$orig;
    }

    return;
};

around app_deploy => sub ( $orig, $self ) {
    if ( !$self->_appx_deployed ) {
        $self->_appx_deployed(1);

        for my $attr ( $self->_appx_enum->@* ) {
            my $attr_reader = $attr->{reader};

            $self->_appx_report_info(qq[Deploy AppX component "$attr_reader"]);

            $self->$attr_reader->app_deploy;
        }

        $self->$orig;
    }

    return;
};

around app_reset => sub ( $orig, $self ) {

    # call reset of included AppX objects
    for my $attr ( @{ $self->_appx_enum } ) {
        my $attr_reader = $attr->{reader};

        my $predicate = $attr->{predicate};

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

use Pcore -class;
use Pcore::AppX::HasAppX;
use Pcore::Util::Text qw[to_camel_case];

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

# CLI
sub CLI ($self) {
    return {
        opt => {
            app => {
                short => undef,
                desc  => 'command (build|deploy|test)',
                isa   => [qw[build deploy test]],
            },
            env => {
                short => 'E',
                desc  => 'set run-time environment (development|test|production)',
                isa   => [qw[development test production]],
            },
        },
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    my $app = $self->new;

    # process -E option
    $app->_set_runtime_env( $opt->{env} ) if $opt->{env};

    if ( $opt->{app} ) {
        if ( $opt->{app} eq 'build' ) {
            $app->_appx_report_info(qq[Build application "@{[$app->name]}"]);
            $app->_appx_report_info(qq[Application data dir "@{[$app->app_dir]}"]);

            $app->app_build;

            $app->_appx_report_info(q[Build completed]);

            exit;
        }
        elsif ( $opt->{app} eq 'deploy' ) {
            $app->_appx_report_info(qq[Deploy application "@{[$app->name]}"]);
            $app->_appx_report_info(qq[Application data dir "@{[$app->app_dir]}"]);

            $app->app_deploy;

            $app->_appx_report_info(q[Deploy completed]);

            exit;
        }
        elsif ( $opt->{app} eq 'test' ) {
            $app->_appx_report_info(qq[Test application "@{[$app->name]}"]);
            $app->_appx_report_info(qq[Application data dir "@{[$app->app_dir]}"]);

            $app->app_test;

            $app->_appx_report_info(q[Test completed]);

            exit;
        }
    }
    else {
        $app->run;
    }

    return;
}

sub BUILD ( $self, $args ) {
    P->hash->merge( $self->cfg, $args->{cfg} ) if $args->{cfg};    # merge default cfg with inline cfg

    P->hash->merge( $self->cfg, $self->_read_local_cfg );          # merge with local cfg

    return;
}

# CFG
sub _build_name_camel_case ($self) {
    return to_camel_case( $self->name, ucfirst => 1 );
}

sub _build_app_dir ($self) {
    my $dir = $ENV->{DATA_DIR} . $self->name . q[/];

    P->file->mkpath($dir);

    return $dir;
}

sub _build_cfg ($self) {
    return $CFG;    # return default cfg
}

sub _build__local_cfg_path ($self) {
    return $self->app_dir . $self->name . q[.perl];
}

sub _read_local_cfg ($self) {
    return -f $self->_local_cfg_path ? P->cfg->load( $self->_local_cfg_path ) : {};
}

sub _create_local_cfg ($self) {

    # create local cfg
    my $local_cfg = { SECRET => P->random->bytes_hex(16), };

    # create AppX local configs
    for my $attr ( @{ $self->_appx_enum } ) {
        my $attr_reader = $attr->{reader};

        $self->$attr_reader->_create_local_cfg($local_cfg);
    }

    return $local_cfg;
}

# RUN-TIME ENVIRONMENT
sub _build_env_is_devel ($self) {
    return $self->runtime_env eq 'development' ? 1 : 0;
}

sub _build_env_is_test ($self) {
    return $self->runtime_env eq 'test' ? 1 : 0;
}

sub _build_env_is_prod ($self) {
    return $self->runtime_env eq 'production' ? 1 : 0;
}

# PHASES
sub run ($self) {
    return $self->app_run;
}

sub app_build ($self) {

    # create local cfg
    $self->_appx_report_info(q[Create local config]);
    my $local_cfg = $self->_create_local_cfg;
    P->hash->merge( $local_cfg, $self->_read_local_cfg );    # override local cfg with already configured values

    # store local config
    $self->_appx_report_info( q[Store local config to "] . $self->_local_cfg_path . q["] );
    P->cfg->store( $self->_local_cfg_path, $local_cfg, readable => 1 );

    return;
}

sub app_deploy ($self) {
    return;
}

sub app_test ($self) {
    return;
}

sub app_run ($self) {

    # create handles
    $self->h->app_run;

    # preload API
    $self->api->app_run;

    return;
}

sub app_reset ($self) {
    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 16                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 24                   │ * Private subroutine/method '_appx_report_fatal' declared but not used                                         │
## │      │ 30                   │ * Private subroutine/method '_appx_report_warn' declared but not used                                          │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
