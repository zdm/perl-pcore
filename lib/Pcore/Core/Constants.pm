package Pcore::Core::Constants;

use Pcore qw[-export];
use Const::Fast qw[];
use Types::Serialiser qw[];    ## no critic qw[Modules::ProhibitEvilModules]

our @EXPORT_OK   = qw[$MSWIN $CRLF $LF $TRUE $FALSE $P $DIST $PROC $STDIN $STDOUT $STDERR];
our %EXPORT_TAGS = (                                                                          #
    CORE => \@EXPORT_OK
);
our @EXPORT = @EXPORT_OK;

our $P;
our $DIST;
our $PROC;

our $STDIN;
our $STDOUT;
our $STDERR;

Const::Fast::const our $MSWIN => $^O =~ /MSWin/sm ? 1 : 0;
Const::Fast::const our $CRLF  => qq[\x0D\x0A];               ## no critic qw[ValuesAndExpressions::ProhibitEscapedCharacters]
Const::Fast::const our $LF    => qq[\x0A];                   ## no critic qw[ValuesAndExpressions::ProhibitEscapedCharacters]
Const::Fast::const our $TRUE  => Types::Serialiser::true;
Const::Fast::const our $FALSE => Types::Serialiser::false;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Constants

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
