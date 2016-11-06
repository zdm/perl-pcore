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

has cfg_path => ( is => 'lazy', isa => Str,     init_arg => undef );    # app instance local config path
has cfg      => ( is => 'lazy', isa => HashRef, init_arg => undef );    # app instance local config

has id             => ( is => 'ro', isa => Str, init_arg => undef );    # app id
has instance_id    => ( is => 'ro', isa => Str, init_arg => undef );    # app instance id
has instance_token => ( is => 'ro', isa => Str, init_arg => undef );    # app instance token

has version => ( is => 'lazy', isa => InstanceOf ['version'], init_arg => undef );                      # app instance version
has router => ( is => 'lazy', isa => ConsumerOf ['Pcore::HTTP::Server::Router'], init_arg => undef );
has api => ( is => 'lazy', isa => Maybe [ ConsumerOf ['Pcore::App::API'] ], init_arg => undef );
has http_server => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::Server'], init_arg => undef );

sub _build_name ($self) {
    return ref($self) =~ s[::][-]smgr;
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
    my $api_class = ref($self) . '::API';

    if ( !exists $INC{ $api_class =~ s[::][/]smgr . '.pm' } ) {
        return if !P->class->find($api_class);

        P->class->load($api_class);
    }

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

# TODO init appliacation
around run => sub ( $orig, $self ) {

    # scan router classes
    $self->router->map;

    if ( $self->api ) {
        my $cv = AE::cv;

        $self->api->init(
            sub ($status) {
                exit if !$status;

                $cv->send;

                return;
            }
        );

        $cv->recv;
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
