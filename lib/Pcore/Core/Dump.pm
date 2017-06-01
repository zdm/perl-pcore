package Pcore::Core::Dump;

use Pcore -export => {
    CORE    => [qw[dump]],
    DEFAULT => [qw[dump]],
};
use Pcore::Core::Dump::Dumper;

sub dump {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my %args = (
        color  => 1,
        tags   => 1,
        indent => 4,
        var    => '$VAR',
        @_[ 1 .. $#_ ],
    );

    return ( $args{var} ? "$args{var} = " : '' ) . bless( \%args, 'Pcore::Core::Dump::Dumper' )->run( $_[0] );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 18                   | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 14                   | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Dump

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
