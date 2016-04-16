package Pcore::API::DockerHub::Repository::Build;

use Pcore -class;

extends qw[Pcore::API::Response];

has repo => ( is => 'ro', isa => InstanceOf ['Pcore::API::DockerHub::Repository'], required => 1 );

sub details ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    return $self->repo->api->request( 'get', "/repositories/@{[$self->repo->id]}/buildhistory/@{[$self->{build_code}]}/", 1, undef, $args{cb} );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::DockerHub::Repository::Build

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
