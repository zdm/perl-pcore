package Pcore::App;

use Pcore -role;
use Pcore::HTTP::Server;
use Pcore::App::Router;

has app_id => ( is => 'ro', isa => Str, required => 1 );
has cluster => ( is => 'ro', isa => Maybe [Str] );    # cluster uri, https://host:port/api/

# HTTP server settings
has listen => ( is => 'ro', isa => Str, required => 1 );
has keepalive_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );

# API settings
has auth => ( is => 'ro', isa => Maybe [ Str | ConsumerOf ['Pcore::DBH'] | ConsumerOf ['Pcore::App::API::Auth'] ] );

has api => ( is => 'lazy', isa => Maybe [ ConsumerOf ['Pcore::App::API'] ], init_arg => undef );
has router      => ( is => 'lazy', isa => ConsumerOf ['Pcore::HTTP::Server::Router'], init_arg => undef );
has http_server => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::Server'],         init_arg => undef );

sub _build_api ($self) {
    my $api_class = eval { P->class->load( 'API', ns => ref $self ) };

    return if $@;

    die qq[API class "$api_class" is not consumer of "Pcore::App::API"] if !$api_class->does('Pcore::App::API');

    return $api_class->new( { app => $self } );
}

sub _build_router ($self) {
    return Pcore::App::Router->new( { app => $self } );
}

sub _build_http_server ($self) {
    return Pcore::HTTP::Server->new(
        {   listen            => $self->listen,
            keepalive_timeout => $self->keepalive_timeout,
            app               => $self->router,
        }
    );
}

# TODO start HTTP server
sub run ($self) {

    # scan router classes
    $self->router->map;

    # die if API controller found, but no API server provided
    die q[API is required] if $self->router->api_class && !$self->api;

    $self->api->upload_api_map;

    $self->http_server->run;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
