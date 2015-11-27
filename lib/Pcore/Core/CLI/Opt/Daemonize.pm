package Pcore::Core::CLI::Opt::Daemonize;

use Pcore qw[-role];

around cli_opt => sub ( $orig, $self ) {
    my $opt = $self->$orig // {};

    if ( !$MSWIN ) {
        $opt->{daemonize} = {
            short => 'D',
            desc  => 'daemonize the process',
        };
    }

    return $opt;
};

around cli_run => sub ( $orig, $self, $opt, @args ) {

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

no Pcore;

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
