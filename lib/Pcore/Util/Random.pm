package Pcore::Util::Random;

use Pcore;
use Math::Random::ISAAC::XS qw[];
use Bytes::Random::Secure qw[];    ## no critic qw[Modules::ProhibitEvilModules]

our $SEED_BITS        = 256;
our $SEED_NONBLOCKING = 1;                                                                       # blocking entropy generator is more secure
our $PASSWORD_SYMBOLS = join q[], ( 0 .. 9, 'a' .. 'z', 'A' .. 'Z', qw[! @ $ % ^ & *], q[#] );
our $PASSWORD_LENGTH  = 16;

my $_PID = $$;

my $_RANDOM;

sub _random {
    if ( $$ ne $_PID ) {
        $_PID    = $$;
        $_RANDOM = undef;
    }

    $_RANDOM //= Bytes::Random::Secure->new( NonBlocking => $SEED_NONBLOCKING, Bits => $SEED_BITS );

    return $_RANDOM;
}

sub bytes ($bytes) {
    return _random->bytes($bytes);
}

sub bytes_hex ($bytes) {
    return _random->bytes_hex($bytes);
}

sub password ($length = $PASSWORD_LENGTH) {
    return _random->string_from( $PASSWORD_SYMBOLS, $length );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 16                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_random' declared but not used      │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Random

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
