package Pcore::Core::CLI::Cmd::Service;

use Pcore -class;

with qw[Pcore::Core::CLI::Cmd];

sub cli_name ($self) {
    return 'service';
}

sub cli_abstract ($self) {
    return 'manage service';
}

sub cli_opt ($self) {
    return {
        name => {
            short => undef,
            desc  => 'service name',
            isa   => 'Str',
            min   => 1,
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
        my $wrapper = $ENV->share->get('/bin/nssm_x64.exe');

        P->pm->run_capture( $wrapper, 'install', $service_name, $^X, $ENV->{SCRIPT_PATH} );
    }
    else {
        my $TMPL = <<"TXT";
[Unit]
After=network.target

[Service]
ExecStart=/bin/bash -c ". /etc/profile; exec $ENV->{SCRIPT_PATH}"
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
