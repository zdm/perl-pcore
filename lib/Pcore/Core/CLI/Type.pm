package Pcore::Core::CLI::Type;

use Pcore qw[-const -types];

const our $TYPE => {
    Str => {
        getopt    => 's',
        validator => sub ($val) {
            return Str->check($val);
        },
    },
    Int => {
        getopt    => 'i',
        validator => sub ($val) {
            return Int->check($val);
        },
    },
    Num => {
        getopt    => 'f',
        validator => sub ($val) {
            return Num->check($val);
        },
    },
    Path => {
        getopt    => 's',
        validator => sub ($val) {
            return -e $val;
        },
    },
    Dir => {
        getopt    => 's',
        validator => sub ($val) {
            return -d $val;
        },
    },
    File => {
        getopt    => 's',
        validator => sub ($val) {
            return -f $val;
        },
    },
};

no Pcore;

sub validate ( $self, $var, $type ) {
    my $vals = ref $var eq 'ARRAY' ? $var : ref $var eq 'HASH' ? [ values $var->%* ] : [$var];

    for ( $vals->@* ) {
        if ( !$TYPE->{$type}->{validator}->($_) ) {
            return qq[value "$_" is not a ] . uc $type;
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
## │    3 │ 47                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
