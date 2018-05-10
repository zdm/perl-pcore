package Pcore::Core::CLI::Opt::Daemonize;

use Pcore -class1;

sub CLI ( $self ) {
    my $cli = $self->SUPER::CLI // {};

    if ( !$MSWIN ) {
        $cli->{opt}->{daemonize} = {
            short => 'D',
            desc  => 'daemonize the process',
        };
    }

    return $cli;
}

# TODO daemonize at runtime
sub CLI_RUN ( $self, $opt, @args ) {

    # set daemonize flag
    $ENV->{DAEMONIZE} = 1 if $opt->{daemonize};

    return $self->SUPER::CLI_RUN( $opt, @args );
}

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
