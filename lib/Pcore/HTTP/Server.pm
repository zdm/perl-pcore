package Pcore::HTTP::Server;

use Pcore -class;
use Pcore::AE::Handle;
use AnyEvent::Socket qw[];
use Pcore::Util::List qw[pairs];

has listen     => ( is => 'ro', isa => Str,               required => 1 );
has backlog    => ( is => 'ro', isa => PositiveOrZeroInt, default  => 0 );
has keep_alive => ( is => 'ro', isa => PositiveOrZeroInt, default  => 10 );
has app        => ( is => 'ro', isa => CodeRef,           required => 1 );

has _listen => ( is => 'lazy', isa => Object, init_arg => undef );
has _request => ( is => 'lazy', isa => PositiveOrZeroInt, default => 0, init_arg => undef );

sub BUILD ( $self, $args ) {
    $self->_listen;

    return;
}

sub _build__listen ($self) {
    my $uri = P->uri( $self->listen, authority => 1, base => 'tcp:' );

    my $accept = sub ( $fh, $host, $port ) {
        $self->_on_accept( $fh, $host, $port );

        return;
    };

    # should return the length of the listen queue (or 0 for the default)
    my $prepare = sub ( $fh, $host, $port ) {
        return $self->backlog;
    };

    if ( $uri->scheme eq 'unix' ) {
        chmod oct 777, $uri->path or die;

        return AnyEvent::Socket::tcp_server( 'unix/', $uri->path, $accept, $prepare );
    }
    else {
        return AnyEvent::Socket::tcp_server( $uri->host || undef, $uri->port, $accept, $prepare );
    }
}

sub _build__handle_cache ($self) {
    return Pcore::AE::Handle::Cache->new( { default_timeout => $self->keep_alive } );
}

sub _on_accept ( $self, $fh, $host, $port ) {
    Pcore::AE::Handle->new(
        fh         => $fh,
        on_connect => sub ( $h, @ ) {
            $self->_wait_request($h);

            return;
        }
    );

    return;
}

sub _wait_request ( $self, $h ) {
    $h->read_http_req_headers(
        sub ( $h1, $env, $error ) {

            # TODO close socker on error

            $self->{_request}++;

            $env->{'psgi.version'}      = [ 1, 1 ];
            $env->{'psgi.url_scheme'}   = 'http';     # TODO http, https
            $env->{'psgi.input'}        = $h;         # TODO
            $env->{'psgi.errors'}       = undef;
            $env->{'psgi.multithread'}  = 0;
            $env->{'psgi.multiprocess'} = 0;
            $env->{'psgi.run_once'}     = 0;
            $env->{'psgi.nonblocking'}  = 1;
            $env->{'psgi.streaming'}    = 1;

            my $res = $self->app->($env);

            if ( ref $res eq 'CODE' ) {
                $res->(
                    sub () {
                        return;
                    }
                );
            }
            elsif ( ref $res eq 'ARRAY' ) {
                my $body = join q[], $res->[2]->@*;

                my $headers = join $CRLF, 'HTTP/1.1 ' . $res->[0], 'Content-Length: ' . length $body, map { $_->key . q[: ] . $_->value } pairs $res->[1]->@*;

                $h->push_write( $headers . $CRLF . $CRLF . $body );
            }
            else {
                die 'Invalid PSGI response from application';
            }

            my $keep_alive = 0;

            if ($keep_alive) {
                $self->_wait_request($h);
            }

            return;
        }
    );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
