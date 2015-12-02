package Pcore::Dist::CLI::Create;

use Pcore qw[-class];

with qw[Pcore::Core::CLI::Cmd];

no Pcore;

# CLI
sub cli_name ($self) {
    return 'new';
}

sub cli_opt ($self) {
    return {
        cpan => {
            desc    => 'create CPAN distribution',
            negated => 1,
            default => 0,
        },
    };
}

sub cli_arg ($self) {
    return [    #
        {   name => 'namespace',
            type => 'Str',
            min  => 1,
        },
    ];
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    require Pcore::Dist::Create;

    $opt->{namespace} = $arg->{namespace};

    $opt->{path} = $PROC->{START_DIR};

    my $create = Pcore::Dist::Create->new($opt);

    if ( my $err = $create->validate ) {
        say $err . $LF;

        exit 3;
    }

    $create->run;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Create - create new distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
