package Pcore::JS::Generator::Call;

use Pcore qw[-class];

with qw[Pcore::JS::Generator::Base];

has func_name => ( is => 'ro', isa => Str, required => 1 );
has func_args => ( is => 'ro', isa => ArrayRef );

no Pcore;

sub as_js {
    my $self = shift;

    my @args;

    for my $arg ( $self->func_args->@* ) {
        push @args, $self->generate_js($arg)->$*;
    }

    return $self->func_name . q[(] . join( q[,], @args ) . q[)];
}

1;
__END__
=pod

=encoding utf8

=cut
