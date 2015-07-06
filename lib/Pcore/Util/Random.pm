package Pcore::Util::Random;

use Pcore;
use Math::Random::ISAAC::XS qw[];
use Bytes::Random::Secure qw[];    ## no critic qw(Modules::ProhibitEvilModules)

our $SEED_BITS        = 256;
our $SEED_NONBLOCKING = 1;                                                                       # blocking entropy generator is more secure
our $PASSWORD_SYMBOLS = join q[], ( 0 .. 9, 'a' .. 'z', 'A' .. 'Z', qw[! @ $ % ^ & *], q[#] );
our $PASSWORD_LENGTH  = 16;

my $_PID = P->sys->pid;
my $_RANDOM;

sub _random {
    my $self = shift;

    my $pid = P->sys->pid;
    if ( $pid ne $_PID ) {
        $_PID    = $pid;
        $_RANDOM = undef;
    }

    $_RANDOM //= Bytes::Random::Secure->new( NonBlocking => $SEED_NONBLOCKING, Bits => $SEED_BITS );

    return $_RANDOM;
}

sub bytes {
    my $self  = shift;
    my $bytes = shift;

    return $self->_random->bytes($bytes);
}

sub bytes_hex {
    my $self  = shift;
    my $bytes = shift;

    return $self->_random->bytes_hex($bytes);
}

sub password {
    my $self = shift;
    my $length = shift || $PASSWORD_LENGTH;

    return $self->_random->string_from( $PASSWORD_SYMBOLS, $length );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Random

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
