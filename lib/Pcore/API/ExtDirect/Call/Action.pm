package Pcore::API::Call::Action;

use Pcore -role;

has type   => ( is => 'ro', isa => Str, default   => 'rpc' );
has action => ( is => 'ro', isa => Str, required  => 1 );
has method => ( is => 'ro', isa => Str, required  => 1 );
has tid    => ( is => 'ro', isa => Int, predicate => 1 );

has data => ( is => 'ro', predicate => 1 );

has _real_action => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

sub _build__real_action {
    my $self = shift;

    return lc $self->action =~ s[/][.]smgr;    # convert to internal dotted format
}

1;
__END__
=pod

=encoding utf8

=cut
