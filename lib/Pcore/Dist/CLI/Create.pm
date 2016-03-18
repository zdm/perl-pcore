package Pcore::Dist::CLI::Create;

use Pcore -class;
use Pcore::Dist;

with qw[Pcore::Core::CLI::Cmd];

# CLI
sub CLI ($self) {
    return {
        abstract => 'create new distribution',
        name     => 'new',
        opt      => {
            cpan => {
                desc    => 'create CPAN distribution',
                default => 0,
            },
            repo => {
                desc    => 'create upstream repository',
                default => 0,
            },
        },
        arg => [    #
            namespace => { type => 'Str', },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
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
## │    3 │ 34                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
