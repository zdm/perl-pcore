package Pcore::Util::Path1::Dir;

use Pcore -role;
use IO::AIO qw[];
use Pcore::Util::Scalar qw[is_plain_coderef];

sub read_dir ( $self, @ ) {
    my $cb = is_plain_coderef $_[-1] ? shift : ();

    my $wantarray = defined wantarray;

    my %args = (
        recursive => 0,
        abs       => 0,
        @_[ 1 .. $#_ ]
    );

    # IO::AIO::READDIR_DENTS
    # IO::AIO::READDIR_DIRS_FIRST
    # IO::AIO::READDIR_STAT_ORDER
    my $flags = IO::AIO::READDIR_DENTS | IO::AIO::READDIR_DIRS_FIRST | IO::AIO::READDIR_STAT_ORDER;

    my $res;

    my $cv = P->cv->begin( sub ($cv) {
        $res = $cb->($res) if defined $cb;

        $cv->($res) if $wantarray;

        return;
    } );

    my $base = $self->{to_string};

    my $read = sub ( $path ) {
        $cv->begin;

        my $sub = __SUB__;

        IO::AIO::aio_readdirx "${base}/$path", $flags, sub ( $entries, $flags ) {
            if ( defined $entries ) {
                for my $item ( $entries->@* ) {
                    push $res->@*,
                      bless {
                        to_string => $args{abs} ? "$base/${path}$item->[0]" : "${path}$item->[0]",
                        _stat_type => $item->[1],
                      },
                      'Pcore::Util::Path1';

                    $sub->("${path}$item->[0]/") if $args{recursive} && $item->[1] == IO::AIO::DT_DIR;
                }
            }

            $cv->end;

            return;
        };

        return;
    };

    $read->('');

    $cv->end;

    return $wantarray ? $cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 62                   | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 12                   | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path1::Dir

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
