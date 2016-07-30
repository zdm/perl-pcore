package Pcore::App::HTTP;

use Pcore -role;
use Pcore::HTTP::Server;
use Pcore::App::HTTP::Router;

has app_id => ( is => 'ro', isa => Str, required => 1 );
has cluster => ( is => 'ro', isa => Maybe [Str] );    # cluster uri, https://host:port/api/

has api => ( is => 'lazy', isa => Maybe [ ConsumerOf ['Pcore::App::HTTP::API'] ], init_arg => undef );
has router      => ( is => 'lazy', isa => ConsumerOf ['Pcore::HTTP::Server::Router'], init_arg => undef );
has http_server => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::Server'],         init_arg => undef );

sub _build_api ($self) {
    my $api_class = eval { P->class->load( 'API', ns => ref $self ) };

    return if $@;

    die qq[API class "$api_class" is not consumer of "Pcore::App::HTTP::API"] if !$api_class->does('Pcore::App::HTTP::API');

    return $api_class->new( { app => $self } );
}

sub _build_router ($self) {
    return Pcore::App::HTTP::Router->new( { app => $self } );
}

sub _build_http_server ($self) {
    return Pcore::HTTP::Server->new(
        {   listen => '127.0.0.1:80',
            app    => $self->router,
        }
    );
}

# TODO start HTTP server
# TODO die if api controller found, but no api server provided
sub run ($self) {
    say dump $self->api->map;

    $self->router;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::HTTP

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
