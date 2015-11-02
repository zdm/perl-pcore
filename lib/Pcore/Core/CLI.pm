package Pcore::Core::CLI;

use Pcore;

our @PACKAGES;

our $HIDDEN_KEYS = {    #
    '---scan-deps' => 0,
};

sub CORE_INIT {
    P->EV->register( 'CORE#CLI' => \&core_cli_event, disposable => 1 );

    return;
}

sub core_cli_event {
    my $ev = shift;

    my @argv;

    for (@ARGV) {
        if ( exists $HIDDEN_KEYS->{$_} ) {
            $HIDDEN_KEYS->{$_} = 1;
        }
        else {
            push @argv, $_;
        }
    }

    require Pcore::Devel::ScanDeps if $HIDDEN_KEYS->{'---scan-deps'};

    require Getopt::Euclid;

    my $pods = [];

    my ( $linux_pod_fh, $service_pod_fh );

    # push main script pod
    if ($Pcore::IS_PAR) {
        unshift $pods->@*, $ENV{PAR_TEMP} . q[/inc/script/main.pl];
    }
    else {
        unshift $pods->@*, $PROC->{SCRIPT_PATH};
    }

    unshift $pods->@*, map { $INC{ s[::][/]smgr . '.pm' } } reverse @PACKAGES;

    # add linux POD
    if ( !$MSWIN ) {
        my $pod = <<'POD';
=pod

=encoding utf8

=head1 OPTIONS

=over

=item -D | --daemonize

Daemonize the process.

=item --UID [=] <uid>

Specify a user id or user name that the server process should switch to.

=item --GID [=] <gid>

Specify the group id or group name that the server should switch to.

=back

=cut
POD

        open $linux_pod_fh, '<', \$pod or die;    ## no critic qw[InputOutput::RequireBriefOpen]

        unshift $pods->@*, $linux_pod_fh;
    }

    # add service POD
    if ( $PROC->{SERVICE_NAME} ) {
        my $pod = <<'POD';
=pod

=encoding utf8

=head1 OPTIONS

=over

=item --install-service [=] [<service-name>]

Install systemd unit. Default name is "$PROC->{SERVICE_NAME}".

=for Euclid:
    service-name.type: /[\\w-]+/

=back

=cut
POD

        open $service_pod_fh, '<', \$pod or die;    ## no critic qw[InputOutput::RequireBriefOpen]

        unshift $pods->@*, $service_pod_fh;
    }

    # process POD
    {
        local $SIG{__WARN__} = sub { };

        Getopt::Euclid->process_pods( $pods, { -strict => $Pcore::IS_PAR ? 0 : 1 } );
    }

    {
        local $SIG{__WARN__} = sub {
            my $e = shift;

            print $e->msg;

            exit 2;    # standart params error exit code
        };

        Getopt::Euclid->process_args( \@argv, { -minimal_keys => 1 } );
    }

    close $linux_pod_fh or die if $linux_pod_fh;

    close $service_pod_fh or die if $service_pod_fh;

    if ( exists $ARGV{install_service} ) {
        _install_service();

        exit 0;
    }

    # store uid and gid
    $PROC->{GID} = $ARGV{GID} if $ARGV{GID};

    $PROC->{UID} = $ARGV{UID} if $ARGV{UID};

    # daemonize
    if ( $ARGV{daemonize} ) {
        P->EV->register(
            'CORE#RUN' => sub {
                P->pm->daemonize;

                return 1;
            },
            disposable => 1
        );
    }

    return;
}

sub _install_service {
    my $service_name = $ARGV{install_service} // $PROC->{SERVICE_NAME};

    if ($MSWIN) {
        my $wrapper = P->res->get_local('nssm_x64.exe');

        my $output = P->capture->sys( $wrapper, 'install', $service_name, 'perl.exe', $PROC->{SCRIPT_PATH} );
    }
    else {
        my $TMPL = <<"TXT";
[Unit]
After=network.target

[Service]
ExecStart=/bin/bash -c ". /etc/profile; exec $PROC->{SCRIPT_PATH}"
Restart=always

[Install]
WantedBy=multi-user.target
TXT
        P->file->write_text( qq[/etc/systemd/system/$service_name.service], { mode => q[rw-r--r--], umask => q[rw-r--r--] }, $TMPL );
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI - pcore CLI interface

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
