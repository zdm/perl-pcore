package Pcore::API::Docker::Engine;

use Pcore -class, -const;

const our $API_VER => 'v1.39';

has host => '/var/run/docker.sock';

# NOTE https://docs.docker.com/engine/api/v1.39/

# IMAGES
# https://docs.docker.com/engine/api/v1.39/#operation/ImageList
sub get_images ($self) {
    return $self->_req( 'GET', 'images/json' );
}

# https://docs.docker.com/engine/api/v1.39/#operation/ImageBuild
sub build_image ($self) {
    return $self->_req( 'POST', 'build' );
}

# CONTAINERS
# https://docs.docker.com/engine/api/v1.39/#operation/ContainerList
sub get_containers ($self) {
    return $self->_req( 'GET', 'containers/json' );
}

sub _req ( $self, $method, $path, $data = undef ) {
    my $url = $self->_create_url($path);

    my $res = P->http->request(
        method => $method,
        url    => $self->_create_url($path),
        data   => $data,
    );

    return P->data->from_json( $res->{data} );
}

sub _create_url ( $self, $path ) {
    my $url;

    my $host = $self->{host};

    if ( substr( $host, 0, 1 ) eq '/' ) {
        $url = "http:///unix:$host:/$API_VER/$path";
    }
    else {
        $url = "http://$host/$API_VER/$path";
    }

    return $url;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Docker::Engine

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
