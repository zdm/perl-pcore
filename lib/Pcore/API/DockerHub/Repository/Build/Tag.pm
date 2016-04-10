package Pcore::API::DockerHub::Repository::Build::Tag;

use Pcore -class;

has repo => ( is => 'ro', isa => InstanceOf ['Pcore::API::DockerHub::Repository'], required => 1 );
has id => ( is => 'ro', isa => Int, required => 1 );

sub remove ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1,
    );

    return $self->repo->api->request( 'delete', "/repositories/@{[$self->repo->id]}/autobuild/tags/@{[$self->id]}/", 1, undef, $args{cb} );
}

sub update ( $self, % ) {
    my %args = (
        cb                  => undef,
        name                => '{sourceref}',    # docker build tag name
        source_type         => 'Tag',            # Branch, Tag
        source_name         => '/.*/',           # barnch / tag name in the source repository
        dockerfile_location => q[/],
        splice @_, 1,
    );

    return $self->repo->api->request(
        'put',
        "/repositories/@{[$self->repo->id]}/autobuilds/tags/@{[$self->id]}/",
        1,
        {   id                  => $self->id,
            name                => $args{name},
            source_type         => $args{source_type},
            source_name         => $args{source_name},
            dockerfile_location => $args{dockerfile_location},
        },
        $args{cb}
    );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::DockerHub::Repository::Build::Tag

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
