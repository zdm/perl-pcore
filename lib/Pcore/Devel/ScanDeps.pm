package Pcore::Devel::ScanDeps;

use Pcore -types;
use Config;
use JSON::XS qw[];    ## no critic qw[Modules::ProhibitEvilModules]

# store values, for access them later during global destruction
our $FN          = $ENV->dist->share_dir . "pardeps-$Config{archname}.json";
our $SCRIPT_NAME = $ENV->{SCRIPT_NAME};
our $DEPS        = {};

if ( $ENV->dist ) {
    our $GUARD = bless {}, __PACKAGE__;

    cluck 'Scanning the PAR dependencies ...';

    # eval TypeTiny Error
    eval { Int->('error') };

    # eval common modules
    require JSON::XS;    ## no critic qw[Modules::ProhibitEvilModules]
}

sub add_deps ( $self, $deps ) {
    $DEPS->@{ keys $deps->%* } = values $deps->%*;

    return;
}

sub DESTROY {
    my $deps;

    # read deps file, if already exists
    if ( -f $FN ) {
        open my $deps_fh, '<:raw', $FN or die;

        local $/;

        $deps = JSON::XS->new->ascii(0)->latin1(0)->utf8(1)->pretty(1)->canonical(1)->decode(<$deps_fh>);

        close $deps_fh or die;
    }

    # add new deps
    for my $pkg ( sort keys %INC ) {
        say 'new deps found: ' . $pkg if !exists $deps->{$SCRIPT_NAME}->{$pkg};

        $deps->{$SCRIPT_NAME}->{$pkg} = 1;
    }

    for my $pkg ( sort keys $DEPS->%* ) {
        say 'new deps found: ' . $pkg if !exists $deps->{$SCRIPT_NAME}->{$pkg};

        $deps->{$SCRIPT_NAME}->{$pkg} = 1;
    }

    # store deps
    open my $deps_fh, '>:raw', $FN or die;

    print {$deps_fh} JSON::XS->new->ascii(0)->latin1(0)->utf8(1)->pretty(1)->canonical(1)->encode($deps);

    close $deps_fh or die;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 18                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 25, 51               | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 37                   | Variables::RequireInitializationForLocalVars - "local" variable not initialized                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 39, 60               | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 7                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Devel::ScanDeps

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
