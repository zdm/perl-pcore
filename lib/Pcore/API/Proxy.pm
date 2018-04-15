package Pcore::API::Proxy;

use Pcore -class, -res;
use Pcore::Util::Scalar qw[is_ref];

has uri => ( is => 'ro', isa => Str | InstanceOf ['Pcore::Util::URI'], required => 1 );

has pool => ( is => 'ro', isa => Maybe [Object] );

has threads => ( is => 'ro', isa => PositiveOrZeroInt, default => 0, init_arg => undef );

sub DEMOLISH ( $self, $global ) {
    if ( !$global ) {
        $self->{threads}--;

        $self->{pool}->push_proxy($self) if defined $self->{pool};
    }

    return;
}

around new => sub ( $orig, $self, $uri ) {
    $uri = P->uri($uri) if !is_ref $uri;

    return $self->$orig( { uri => $uri } );
};

sub connect_http ( $self, $target, @args ) {
    my $cb = pop @args;

    Pcore::AE::Handle->new(
        connect => $self->{uri},
        @args,

        # connect_timeout  => $args->{connect_timeout},
        # timeout          => $args->{timeout},
        # tls_ctx          => $args->{tls_ctx},
        # bind_ip          => $args->{bind_ip},

        on_connect_error => sub ( $h, $reason ) {
            $cb->( undef, res [ 600, $reason ] );

            return;
        },
        on_connect => sub ( $h, $host, $port, $retry ) {
            $self->{threads}++;

            $cb->( $h, res 200 );

            return;
        },
    );

    return;
}

sub connect_https ( $self, $target, @args ) {
    my $cb = pop @args;

    Pcore::AE::Handle->new(
        connect => $self->{uri},
        @args,

        # connect_timeout  => $args->{connect_timeout},
        # timeout          => $args->{timeout},
        # tls_ctx          => $args->{tls_ctx},
        # bind_ip          => $args->{bind_ip},

        on_connect_error => sub ( $h, $reason ) {
            $cb->( undef, res [ 600, $reason ] );

            return;
        },
        on_connect => sub ( $h, $host, $port, $retry ) {
            my $buf = 'CONNECT ' . $target->hostport . q[ HTTP/1.1] . $CRLF;

            $buf .= 'Proxy-Authorization: Basic ' . $self->{uri}->userinfo_b64 . $CRLF if $self->{uri}->userinfo;

            $buf .= $CRLF;

            $h->push_write($buf);

            $h->read_http_res_headers(
                headers => 0,
                sub ( $h1, $res, $error_reason ) {
                    if ($error_reason) {
                        $cb->( undef, res [ 600, 'Invalid proxy connect response' ] );
                    }
                    else {
                        if ( $res->{status} == 200 ) {
                            $h->{peername} = $target->host;

                            $self->{threads}++;

                            $cb->( $h, res 200 );
                        }
                        elsif ( $res->{status} == 407 ) {
                            $cb->( undef, res [ 407, $res->{reason} ] );
                        }
                        else {
                            $cb->( undef, res [ $res->{status}, $res->{reason} ] );
                        }
                    }

                    return;
                }
            );

            return;
        },
    );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Proxy

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
