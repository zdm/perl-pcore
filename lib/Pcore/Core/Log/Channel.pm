package Pcore::Core::Log::Channel;

use Pcore -role;

has channel => ( is => 'lazy', isa => Str, default => sub { lc ref( $_[0] ) =~ s/\A.+:://smr }, init_arg => undef );
has stream  => ( is => 'ro',   isa => Str, default => q[] );
has header  => ( is => 'ro',   isa => Str, default => '[%H:%M:%S.%3N][%ID][%NS][%LEVEL] ' );
has priority => ( is => 'ro', isa => Int,  default => 1, init_arg => undef );
has color    => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

sub id {
    my $self = shift;
    my %args = (
        header => undef,
        @_
    );

    return P->digest->md5_hex( $self->channel . $self->stream . ( $args{header} // $self->header ) );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Log::Channel

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
