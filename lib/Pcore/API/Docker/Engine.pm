package Pcore::API::Docker::Engine;

use Pcore -class, -const;

const our $API_VER               => 'v1.39';
const our $DEFAULT_BUILD_TIMEOUT => 60 * 60 * 2;

has host          => '/var/run/docker.sock';
has build_timeout => $DEFAULT_BUILD_TIMEOUT;

# NOTE https://docs.docker.com/engine/api/v1.39/

# IMAGES
# https://docs.docker.com/engine/api/v1.39/#operation/ImageList
sub get_images ($self) {
    return $self->_req( 'GET', 'images/json' );
}

# https://docs.docker.com/engine/api/v1.39/#operation/ImageBuild
sub build_image ( $self, $tar, $tags ) {
    my $params = [

        # squash  => 1,                       # NOTE not works, squash the resulting images layers into a single layer
        rm      => 1,    # remove intermediate containers after a successful build
        forcerm => 1,    # always remove intermediate containers, even upon failure
        nocache => 1,    # do not use the cache when building the image
        pull    => 1,    # attempt to pull the image even if an older image exists locally
    ];

    for ( $tags->@* ) { push $params->@*, t => $_ }

    my $url = $self->_create_url('build') . '?' . P->data->to_uri($params);

    my $res = P->http->request(
        method  => 'POST',
        url     => $url,
        data    => $tar,
        timeout => $self->{build_timeout},
    );

    return res $res if !$res;

    my ( $log, $error );

    for my $stream ( split /\r\n/sm, $res->{data}->$* ) {
        my $data = P->data->from_json($stream);

        $log .= $data->{stream} if exists $data->{stream};

        $erorr = 1 if exists $data->{error};
    }

    return res 500, log => $log if $error;

    return res 200;
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
        url    => $url,
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
