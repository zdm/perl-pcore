package Pcore::Core::Const;

use common::header;
use Const::Fast qw[const];

# <<<
const our $ANSI => {
    reset          => 0,
    bold           => 1,
    dark           => 2,
    italic         => 3,
    underline      => 4,
    blink          => 5,
    reverse        => 7,
    concealed      => 8,

    black          => 30,   on_black          => 40,
    red            => 31,   on_red            => 41,
    green          => 32,   on_green          => 42,
    yellow         => 33,   on_yellow         => 43,
    blue           => 34,   on_blue           => 44,
    magenta        => 35,   on_magenta        => 45,
    cyan           => 36,   on_cyan           => 46,
    white          => 37,   on_white          => 47,

    bright_black   => 90,   on_bright_black   => 100,
    bright_red     => 91,   on_bright_red     => 101,
    bright_green   => 92,   on_bright_green   => 102,
    bright_yellow  => 93,   on_bright_yellow  => 103,
    bright_blue    => 94,   on_bright_blue    => 104,
    bright_magenta => 95,   on_bright_magenta => 105,
    bright_cyan    => 96,   on_bright_cyan    => 106,
    bright_white   => 97,   on_bright_white   => 107,
};
# >>>

for my $name ( keys $ANSI->%* ) {
    my $esc = "\e[$ANSI->{$name}m";

    eval    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
      qq[
        package _Pcore::Core::Const::ANSI::$name {
            use overload q[""] => sub {
                if   ( !\$ENV{ANSI_COLORS_DISABLED} ) { return "$esc" }
                else                                  { return q[] }
            };
        };

        const our \$@{[ uc $name ]} => bless {}, '_Pcore::Core::Const::ANSI::$name';
    ];
}

require Pcore::Core::Exporter;
Pcore::Core::Exporter->import(
    -export => {
        CORE    => [qw[$MSWIN $CRLF $LF $TRUE $FALSE $STDOUT_UTF8 $STDERR_UTF8]],
        DEFAULT => [':CORE'],
        ANSI    => [ map { '$' . uc } keys $ANSI->%* ],
    }
);

our $STDOUT_UTF8;
our $STDERR_UTF8;

const our $MSWIN => $^O =~ /MSWin/sm ? 1 : 0;
const our $CRLF => qq[\x0D\x0A];    ## no critic qw[ValuesAndExpressions::ProhibitEscapedCharacters]
const our $LF   => qq[\x0A];        ## no critic qw[ValuesAndExpressions::ProhibitEscapedCharacters]

use Types::Serialiser qw[];
const our $TRUE  => Types::Serialiser::true;
const our $FALSE => Types::Serialiser::false;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 40                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 41                   | ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 1                    | Modules::RequireVersionVar - No package-scoped "$VERSION" variable found                                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Const

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
