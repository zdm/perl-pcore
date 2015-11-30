package Pcore::Core::CLI::Type;

use Pcore qw[-role -const];

const our $TYPE => {
    Str => sub ($val) {
        return Str->check($val);
    },
    Int => sub ($val) {
        return Int->check($val);
    },
    PositiveInt => sub ($val) {
        return PositiveInt->check($val);
    },
    PositiveOrZeroInt => sub ($val) {
        return PositiveOrZeroInt->check($val);
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

sub _validate_isa ( $self, $var ) {
    my $vals = ref $var eq 'ARRAY' ? $var : ref $var eq 'HASH' ? [ values $var->%* ] : [$var];

    my $isa_ref = ref $self->isa;

    for my $val ( $vals->@* ) {
        if ( !$isa_ref ) {
            return qq[value "$val" is not a ] . uc $self->isa if !$TYPE->{ $self->isa }->($val);
        }
        elsif ( $isa_ref eq 'CODE' ) {
            if ( my $error_msg = $self->isa->($val) ) {
                return $error_msg;
            }
        }
        elsif ( $isa_ref eq 'Regexp' ) {
            return qq[value "$val" should match regexp ] . $self->isa if $val !~ $self->isa;
        }
        elsif ( $isa_ref eq 'ARRAY' ) {
            return qq[value "$val" should be one of the: ] . join q[, ], map {qq["$_"]} $self->isa->@* unless $val ~~ $self->isa;
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
## │    3 │ 34                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_validate_isa' declared but not     │
## │      │                      │ used                                                                                                           │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 35                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
