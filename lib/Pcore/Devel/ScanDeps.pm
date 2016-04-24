package Pcore::Devel::ScanDeps;

use Pcore -types;
use Config;
use CBOR::XS qw[];

# store values, for access them later during global destruction
our $FN          = "$ENV->{DATA_DIR}.pardeps.cbor";
our $SCRIPT_NAME = $ENV->{SCRIPT_NAME};
our $ARCHNAME    = $Config{archname};
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

        $deps = CBOR::XS::decode_cbor(<$deps_fh>);

        close $deps_fh or die;
    }

    # add new deps
    for my $pkg ( sort keys %INC ) {
        say 'new deps found: ' . $pkg if !exists $deps->{$SCRIPT_NAME}->{$ARCHNAME}->{$pkg};

        $deps->{$SCRIPT_NAME}->{$ARCHNAME}->{$pkg} = $INC{$pkg};
    }

    for my $pkg ( sort keys $DEPS->%* ) {
        say 'new deps found: ' . $pkg if !exists $deps->{$SCRIPT_NAME}->{$ARCHNAME}->{$pkg};

        $deps->{$SCRIPT_NAME}->{$ARCHNAME}->{$pkg} = $DEPS->{$pkg};
    }

    # store deps
    open my $deps_fh, '>:raw', $FN or die;

    print {$deps_fh} CBOR::XS::encode_cbor($deps);

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
## |    3 | 19                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 26, 52               | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 38                   | Variables::RequireInitializationForLocalVars - "local" variable not initialized                                |
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
