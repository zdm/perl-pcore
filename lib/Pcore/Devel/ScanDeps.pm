package Pcore::Devel::ScanDeps;

use Pcore;
use Config;
use CBOR::XS qw[];

# store values, for access them later during global destruction
our $FN          = "$ENV->{DATA_DIR}.pardeps.cbor";
our $SCRIPT_NAME = $ENV->{SCRIPT_NAME};
our $ARCHNAME    = $Config{archname};
our $DEPS        = {};

if ( $ENV->dist ) {
    our $GUARD = bless {}, __PACKAGE__;

    core_support();
}

# stolen from Perl::LibExtractor
sub core_support {
    ## no critic

    my $v;
    open my $fh, "<", \$v;
    close $fh;

    my $x = chr 1234;

    my $cc = "\u$x\U$x\l$x\L$x";

    $x =~ /$_$x?/i for qw[\d \w \s \b \R \h \v];

    my @dd = split " ", $x;    # usually covered by the regex above

    $x =~ /\x{1234}(?<a>)\g{a}/;

    return;
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
## |    3 | 21                   | Miscellanea::ProhibitUnrestrictedNoCritic - Unrestricted '## no critic' annotation                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 41, 67               | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 53                   | Variables::RequireInitializationForLocalVars - "local" variable not initialized                                |
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
