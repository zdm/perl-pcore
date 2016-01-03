package Pcore::Util::PM::RPC::Server::Wrapper;

use strict;
use warnings;

our $BOOT_ARGS;

BEGIN {
    require CBOR::XS;

    $BOOT_ARGS = CBOR::XS::decode_cbor( pack 'H*', shift @ARGV );

    $0 = $BOOT_ARGS->{script}->{path};    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    $main::VERSION = version->new( $BOOT_ARGS->{script}->{version} );
}

package                                   # hide from CPAN
  main;

use Pcore;
use Pcore::AE::Handle;
use if $MSWIN, 'Win32API::File';

if ($MSWIN) {
    Win32API::File::OsFHandleOpen( *IN,  $BOOT_ARGS->{ipc}->{in},  'r' ) or die $!;
    Win32API::File::OsFHandleOpen( *OUT, $BOOT_ARGS->{ipc}->{out}, 'w' ) or die $!;
}
else {
    open *IN,  '<&=', $BOOT_ARGS->{ipc}->{in}  or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
    open *OUT, '>&=', $BOOT_ARGS->{ipc}->{out} or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
}

my $cv = AE::cv;

$cv->begin;

Pcore::AE::Handle->new(
    fh         => \*IN,
    on_connect => sub ( $h, @ ) {
        $BOOT_ARGS->{args}->{in} = $h;

        $cv->end;

        return;
    }
);

$cv->begin;

Pcore::AE::Handle->new(
    fh         => \*OUT,
    on_connect => sub ( $h, @ ) {
        $BOOT_ARGS->{args}->{out} = $h;

        $cv->end;

        return;
    }
);

$cv->recv;

$BOOT_ARGS->{args}->{cv} = AE::cv;

$BOOT_ARGS->{args}->{scan_deps} = $BOOT_ARGS->{scan_deps};

my $obj = P->class->load( $BOOT_ARGS->{class} )->new( $BOOT_ARGS->{args} );

# handshake, send PID
$BOOT_ARGS->{args}->{out}->push_write("READY$$\x00");

$BOOT_ARGS->{args}->{cv}->recv;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 71                   │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC::Server::Wrapper

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
