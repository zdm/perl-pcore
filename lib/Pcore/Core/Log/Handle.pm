package Pcore::Core::Log::Handle;

use Pcore -class;
use MooseX::GlobRef;
use IO::Handle;

extends qw[Moose::Object IO::Handle];

with qw[MooseX::GlobRef::Role::Object];

has level => ( is => 'ro', isa => Enum [qw[FATAL ERROR WARN INFO DEBUG]], default => 'INFO' );
has ns     => ( is => 'ro', isa => Str, default   => q[] );
has header => ( is => 'ro', isa => Str, predicate => 1 );

sub print {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my $self   = shift;
    my @caller = caller;

    return Pcore::Core::Log::send_log( \@_, level => $self->level, ns => $self->ns || $caller[0], header => $self->has_header ? $self->header : undef, tags => { package => $caller[0], filename => $caller[1], line => $caller[2], subroutine => $caller[3] } );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Log::Handle

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
