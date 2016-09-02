package Pcore::App;

use Pcore -role;
use Pcore::HTTP::Server;
use Pcore::App::Router;

has name => ( is => 'lazy', isa => Str );
has desc => ( is => 'lazy', isa => Str );

# API settings
has auth => ( is => 'ro', isa => Str, required => 1 );    # db, http or was uri

# HTTP server settings
has listen => ( is => 'ro', isa => Str, required => 1 );
has keepalive_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );

has cfg_path => ( is => 'lazy', isa => Str,     init_arg => undef );
has cfg      => ( is => 'lazy', isa => HashRef, init_arg => undef );

has token => ( is => 'ro', isa => Str, init_arg => undef );

has version => ( is => 'lazy', isa => InstanceOf ['version'], init_arg => undef );
has router => ( is => 'lazy', isa => ConsumerOf ['Pcore::HTTP::Server::Router'], init_arg => undef );
has api => ( is => 'lazy', isa => Maybe [ ConsumerOf ['Pcore::App::API'] ], init_arg => undef );
has http_server => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::Server'], init_arg => undef );

sub _build_name ($self) {
    return ref $self;
}

# TODO get description from POD abstract or die
sub _build_desc ($self) {
    return 'test application';
}

sub _build_cfg_path ($self) {
    return ( $ENV->{DATA_DIR} // q[] ) . ( $self->name =~ s/::/-/smgr ) . '.json';
}

sub _build_cfg ($self) {
    if ( -f $self->cfg_path ) {
        return P->cfg->load( $self->cfg_path );
    }
    else {
        return {};
    }
}

sub _build_version ($self) {
    no strict qw[refs];

    return ${ ref($self) . '::VERSION' };
}

sub _build_router ($self) {
    return Pcore::App::Router->new( { app => $self } );
}

sub _build_api ($self) {
    return if !P->class->find( 'API', ns => ref $self );

    my $api_class = P->class->load( 'API', ns => ref $self );

    die qq[API class "$api_class" is not consumer of "Pcore::App::API"] if !$api_class->does('Pcore::App::API');

    return $api_class->new( { app => $self } );
}

sub _build_http_server ($self) {
    return Pcore::HTTP::Server->new(
        {   listen            => $self->listen,
            keepalive_timeout => $self->keepalive_timeout,
            app               => $self->router,
        }
    );
}

around run => sub ( $orig, $self ) {

    # scan router classes
    $self->router->map;

    if ( $self->api ) {
        $self->api->upload_api_map;
    }
    else {
        # die if API controller found, but no API server provided
        die q[API is required] if $self->router->api_class && !$self->api;
    }

    $self->$orig;

    $self->http_server->run;

    return;
};

# this method can be overloaded in subclasses
sub run ($self) {
    return;
}

sub store_cfg ($self) {
    P->cfg->store( $self->cfg_path, $self->cfg );

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
