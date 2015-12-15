package Pcore::Core::Const;

use Pcore qw[-export -const];

use Types::Serialiser qw[];    ## no critic qw[Modules::ProhibitEvilModules]

our $EXPORT = {
    ALL     => [qw[$MSWIN $CRLF $LF $TRUE $FALSE $PROC $STDOUT_UTF8 $STDERR_UTF8]],
    CORE    => [':ALL'],
    DEFAULT => [':ALL'],
};

our $PROC;

our $STDOUT_UTF8;
our $STDERR_UTF8;

const our $MSWIN => $^O =~ /MSWin/sm ? 1 : 0;
const our $CRLF  => qq[\x0D\x0A];               ## no critic qw[ValuesAndExpressions::ProhibitEscapedCharacters]
const our $LF    => qq[\x0A];                   ## no critic qw[ValuesAndExpressions::ProhibitEscapedCharacters]
const our $TRUE  => Types::Serialiser::true;
const our $FALSE => Types::Serialiser::false;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Const

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
