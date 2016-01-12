package Pcore::AE::Handle::IPPool;

use Pcore -class;

has ip => ( is => 'ro', isa => ArrayRef, required => 1 );

has ip_tag => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

sub get ( $self, $tag ) {
    my $ip_tag = $self->ip_tag;

    if ( !exists $ip_tag->{$tag} ) {
        $ip_tag->{$tag} = 0;
    }
    else {
        ++$ip_tag->{$tag};

        $ip_tag->{$tag} = 0 if $ip_tag->{$tag} > $self->ip->$#*;
    }

    return $self->ip->[ $ip_tag->{$tag} ];
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::Handle::IPPool

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
