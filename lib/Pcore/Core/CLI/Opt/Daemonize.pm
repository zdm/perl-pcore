package Pcore::Core::CLI::Opt::Daemonize;

use Pcore -role;

around CLI => sub ( $orig, $self ) {
    my $cli = $self->$orig // {};

    if ( !$MSWIN ) {
        $cli->{opt}->{daemonize} = {
            short => 'D',
            desc  => 'daemonize the process',
        };
    }

    return $cli;
};

around CLI_RUN => sub ( $orig, $self, $opt, @args ) {

    # daemonize
    if ( $opt->{daemonize} ) {
        P->EV->register(
            'CORE#RUN' => sub {
                P->pm->daemonize;

                return 1;
            },
            disposable => 1
        );
    }

    return $self->$orig( $opt, @args );
};

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Opt::Daemonize

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
