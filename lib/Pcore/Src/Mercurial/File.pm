package Pcore::Src::Mercurial::File;

use Pcore qw[-class];

has path => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Path'], required => 1 );
has status => ( is => 'ro', isa => Enum [qw[A M R ? !]], required => 1 );

sub is_added {
    my $self = shift;

    return $self->status eq 'A' ? 1 : 0;
}

sub is_modified {
    my $self = shift;

    return $self->status eq 'M' ? 1 : 0;
}

sub is_removed {
    my $self = shift;

    return $self->status eq 'R' ? 1 : 0;
}

sub is_missed {
    my $self = shift;

    return $self->status eq q[!] ? 1 : 0;
}

sub is_unknown {
    my $self = shift;

    return $self->status eq q[?] ? 1 : 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::Mercurial::File

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
