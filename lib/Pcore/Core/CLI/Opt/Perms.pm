package Pcore::Core::CLI::Opt::Perms;

use Pcore -role;

around cli_opt => sub ( $orig, $self ) {
    my $opt = $self->$orig // {};

    if ( !$MSWIN ) {
        $opt->{UID} = {
            short => undef,
            desc  => 'specify a user id or user name that the server process should switch to',
        };

        $opt->{GID} = {
            short => undef,
            desc  => 'specify the group id or group name that the server should switch to',
        };
    }

    return $opt;
};

around cli_run => sub ( $orig, $self, $opt, @args ) {

    # store uid and gid
    $PROC->{UID} = $opt->{UID} if $opt->{UID};

    $PROC->{GID} = $opt->{GID} if $opt->{GID};

    return $self->$orig( $opt, @args );
};

no Pcore;

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
