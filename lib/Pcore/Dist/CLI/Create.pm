package Pcore::Dist::CLI::Create;

use Pcore -class;
use Pcore::Dist;

with qw[Pcore::Core::CLI::Cmd];

no Pcore;

# CLI
sub cli_abstract ($self) {
    return 'create new distribution';
}

sub cli_name ($self) {
    return 'new';
}

sub cli_opt ($self) {
    return {
        cpan => {
            desc    => 'create CPAN distribution',
            default => 0,
        },
    };
}

sub cli_arg ($self) {
    return [    #
        {   name => 'namespace',
            type => 'Str',
        },
    ];
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $opt->{namespace} = $arg->{namespace};

    $opt->{path} = $ENV->{START_DIR};

    if ( my $dist = Pcore::Dist->create( $opt->%* ) ) {
        return;
    }
    else {
        say $Pcore::Dist::Build::Create::ERROR . $LF;

        exit 3;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 41                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
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
