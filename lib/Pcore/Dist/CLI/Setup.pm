package Pcore::Dist::CLI::Setup;

use Pcore qw[-class];

with qw[Pcore::Core::CLI::Cmd];

no Pcore;

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run;

    return;
}

sub run ($self) {
    my $cfg = [
        _ => [
            author           => q[],
            email            => q[],
            license          => 'Perl_5',
            copyright_holder => q[],
        ],
        PAUSE => [
            username  => q[],
            passwword => q[],
        ],
        Bitbucket => [ username => q[], ],
        DockerHub => [ username => q[], ],
    ];

    my $config_path = $PROC->{PCORE_USER_DIR} . 'config.ini';

    exit 0 if -f $config_path && P->term->prompt( qq["$config_path" already exists. Overwrite?], [qw[yes no]], enter => 1 ) eq 'no';

    P->cfg->store( $config_path, $cfg );

    say qq["$config_path" was created, fill it manually with correct values];

    exit 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Setup - setup pcore.ini

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
