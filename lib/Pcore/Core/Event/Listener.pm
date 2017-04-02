package Pcore::Core::Event::Listener;

use Pcore -class;
use Pcore::Util::Scalar qw[refaddr];

has event => ( is => 'ro', isa => InstanceOf ['Pcore::Core::Event'], required => 1 );
has keys => ( is => 'ro', isa => ArrayRef, required => 1 );
has cb   => ( is => 'ro', isa => CodeRef,  required => 1 );

has _refaddr => ( is => 'ro', isa => Str, init_arg => undef );

sub BUILD ( $self, $args ) {
    $self->{_refaddr} = refaddr $self;

    return;
}

sub DEMOLISH ( $self, $global ) {
    $self->remove if !$global;

    return;
}

sub remove ($self) {
    for my $key ( $self->{keys}->@* ) {
        my $listeners = $self->{event}->{listeners}->{$key};

        for ( my $i = $listeners->$#*; $i >= 0; $i-- ) {
            if ( !defined $listeners->[$i] || $listeners->[$i]->{_refaddr} eq $self->{_refaddr} ) {
                splice $listeners->@*, $i, 1;
            }
        }

        delete $self->{event}->{listeners}->{$key} if !$self->{event}->{listeners}->{$key}->@*;
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 28                   | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Event::Listener

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
