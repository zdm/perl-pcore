package Pcore::App;

use Pcore -role;
use Pcore::HTTP::Server;
use Pcore::App::Router;
use Pcore::App::API;

has devel => ( is => 'ro', isa => Bool, default => 0 );

# HTTP server settings
has listen => ( is => 'ro', isa => Str, required => 1 );
has keepalive_timeout => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );

has router => ( is => 'ro', isa => InstanceOf ['Pcore::App::Router'], init_arg => undef );
has api => ( is => 'ro', isa => Maybe [ ConsumerOf ['Pcore::App::API'] ], init_arg => undef );
has http_server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], init_arg => undef );

sub BUILD ( $self, $args ) {

    # create HTTP router
    $self->{router} = Pcore::App::Router->new( { hosts => $args->{hosts} // { '*' => ref $self }, app => $self } );

    # init api
    $self->{api} = Pcore::App::API->new( $self, $args->{auth} ) if $args->{auth};

    return;
}

# TODO init appliacation
around run => sub ( $orig, $self, $cb = undef ) {
    my $cv = AE::cv sub {
        $self->$orig( sub {

            # start HTTP server
            $self->{http_server} = Pcore::HTTP::Server->new( {
                listen            => $self->listen,
                keepalive_timeout => $self->keepalive_timeout,
                app               => $self->router,
            } );

            $self->{http_server}->run;

            say qq[Listen: @{[$self->listen]}] if $self->listen;
            say qq[App "@{[ref $self]}" started];

            $cb->($self) if $cb;

            return;
        } );

        return;
    };

    # scan router classes
    print 'Scanning HTTP controllers ... ';
    $self->{router}->init;
    say 'done';

    if ( $self->{api} ) {

        # connect api
        $self->{api}->init( sub ($res) {
            say 'API initialization ... ' . $res;

            exit 3 if !$res;

            $cv->send;

            return;
        } );
    }
    else {

        # die if API controller found, but no API server provided
        die q[API is required] if $self->{router}->{host_api_path} && !$self->{api};

        $cv->send;
    }

    return $self;
};

# this method can be overloaded in subclasses
sub run ($self) {
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

=head1 API METHOD PERMISSSIONS

=over

=item undef

allows to call API method without authentication.

=item "*"

allows any authenticated user.

=item ArrayRef[Str]

array of roles names, that are allowed to run this method.

=back

=head1 SEE ALSO

=cut
