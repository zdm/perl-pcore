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

    if ( my $home = $ENV{HOME} || $ENV{USERPROFILE} ) {
        if ( $home . q[/.pcore/config.ini] ) {
            exit 0 if P->term->prompt( qq["$home/.pcore/config.ini" already exists. Overwrite?], [qw[yes no]] ) eq 'no';
        }

        P->cfg->store( $home . q[/.pcore/config.ini], $cfg );

        say qq["$home/.pcore/config.ini" was created, fill it manually with correct values];

        exit 0;
    }
    else {
        say 'User homedir was not found';

        exit 3;
    }
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
