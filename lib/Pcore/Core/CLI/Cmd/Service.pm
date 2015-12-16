package Pcore::Core::CLI::Cmd::Service;

use Pcore -class;

with qw[Pcore::Core::CLI::Cmd];

no Pcore;

# TODO this command should be added automatically, if $PROC->{CFG}->{SERVICE_NAME} is defined

sub cli_name ($self) {
    return 'service';
}

sub cli_abstract ($self) {
    return 'manage service';
}

sub cli_opt ($self) {
    return {
        name => {
            short   => undef,
            desc    => 'service name',
            isa     => 'Str',
            default => $PROC->{CFG}->{SERVICE_NAME},
        }
    };
}

sub cli_arg ($self) {
    return [
        {   name => 'action',
            isa  => [qw[install]],
        }
    ];
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->_install_service( $opt->{name} ) if $arg->{action} eq 'install';

    exit;
}

sub _install_service ( $self, $service_name ) {
    if ($MSWIN) {
        my $wrapper = $PROC->res->get('/bin/nssm_x64.exe');

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

Pcore::Core::CLI::Cmd::Service

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
