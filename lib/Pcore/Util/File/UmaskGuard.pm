package Pcore::Util::File::UmaskGuard;

use Pcore qw[-class];

use overload    #
  q[""] => sub {
    my $self = shift;

    return $self->old_umask;
  },
  fallback => undef;

has old_umask => ( is => 'ro', isa => Int, required => 1 );

no Pcore;

sub DEMOLISH {
    my $self = shift;

    umask $self->old_umask;    ## no critic qw(InputOutput::RequireCheckedSyscalls)

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File::UmaskGuard

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
