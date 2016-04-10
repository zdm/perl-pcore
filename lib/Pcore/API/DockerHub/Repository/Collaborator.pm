package Pcore::API::DockerHub::Repository::Collaborator;

use Pcore -class;

extends qw[Pcore::API::Response];

has repo => ( is => 'ro', isa => InstanceOf ['Pcore::API::DockerHub::Repository'], required => 1 );
has id => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_id($self) {
    return $self->{user};
}

sub remove ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    return $self->repo->api->request(
        'delete',
        "/repositories/@{[$self->repo->id]}/collaborators/@{[$self->id]}/",
        1, undef,
        sub ($res) {
            $res->{status} = 200 if $res->{status} == 204;

            $args{cb}->($res) if $args{cb};

            return;
        }
    );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::DockerHub::Repository::Collaborator

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
