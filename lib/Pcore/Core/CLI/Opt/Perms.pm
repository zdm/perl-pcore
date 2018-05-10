package Pcore::Core::CLI::Opt::Perms;

use Pcore -class1;

sub CLI ( $self ) {
    my $cli = $self->SUPER::CLI // {};

    if ( !$MSWIN ) {
        $cli->{opt}->{UID} = {
            short => undef,
            desc  => 'specify a user id or user name that the server process should switch to',
        };

        $cli->{opt}->{GID} = {
            short => undef,
            desc  => 'specify the group id or group name that the server should switch to',
        };
    }

    return $cli;
}

sub CLI_RUN ( $self, $opt, @args ) {

    # store uid and gid
    $ENV->{UID} = $opt->{UID} if $opt->{UID};

    $ENV->{GID} = $opt->{GID} if $opt->{GID};

    return $self->SUPER::CLI_RUN( $opt, @args );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Opt::Perms

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
