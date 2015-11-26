package Pcore::Core::CLI::Type;

use Pcore qw[-const -types];

const our $TYPE => {
    Str => sub ($val) {
        return Str->check($val);
    },
    Int => sub ($val) {
        return Int->check($val);
    },
    Num => sub ($val) {
        return Num->check($val);
    },
    Path => sub ($val) {
        return -e $val;
    },
    Dir => sub ($val) {
        return -d $val;
    },
    File => sub ($val) {
        return -f $val;
    },
};

no Pcore;

sub validate ( $self, $opt, $type ) {
    my $vals = ref $opt eq 'ARRAY' ? $opt : ref $opt eq 'HASH' ? [ values $opt->%* ] : [$opt];

    my $type_ref = ref $type;

    for my $val ( $vals->@* ) {
        if ( !$type_ref ) {
            if ( !$TYPE->{$type}->($val) ) {
                return qq[value "$val" is not a ] . uc $type;
            }
        }
        elsif ( $type_ref eq 'CODE' ) {
            if ( my $error_msg = $type->($val) ) {
                return $error_msg;
            }
        }
        elsif ( $type_ref eq 'Regexp' ) {
            return qq[value "$val" should match regexp ] . $type if $val !~ $type;
        }
        elsif ( $type_ref eq 'ARRAY' ) {
            return qq[value "$val" should be one of the: ] . join q[, ], map {qq["$_"]} $type->@* unless $val ~~ $type;
        }
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 29                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Type

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
