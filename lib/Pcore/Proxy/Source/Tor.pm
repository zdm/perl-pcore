package Pcore::Proxy::Source::Tor;

use Pcore qw[-class];

with qw[Pcore::Proxy::Source];

has host            => ( is => 'ro', isa => Str,         default   => '127.0.0.1' );
has port            => ( is => 'ro', isa => PositiveInt, default   => 9050 );
has control_port    => ( is => 'ro', isa => PositiveInt, default   => 9051 );
has password        => ( is => 'ro', isa => Str,         predicate => 1 );
has switch_identity => ( is => 'ro', isa => Bool,        default   => 0 );             # switch identity before each connection

has '+load_timeout' => ( default => 0 );

around get_proxy => sub ( $orig, $self, @args ) {
    my $proxy = $self->$orig(@args);

    $self->new_identity if $proxy and $self->switch_identity;

    return $proxy;
};

no Pcore;

# NOTE it's important to use "persistent" = 0 in AnyEvent::HTTP, otherwise all connections will not use NEWNYM, if NYM changed

sub load ( $self, $cb ) {
    $cb->( [ q[//] . $self->host . q[:] . $self->port ] );

    return;
}

sub update_proxy_status ( $self, $proxy ) {

    # don't ban proxy, get new identity instead
    if ( $proxy->is_banned ) {
        $self->new_identity;

        $proxy->_set_is_banned(0);

        return;
    }

    $self->_pool->update_proxy_status($proxy);

    return;
}

sub id ($self) {
    return $self->_id;
}

# TODO connection cache not work
sub new_identity ($self) {
    my $cache_key = 'tor_control_server_' . $self->host . q[:] . $self->control_port;

    my $h = Pcore::AE::Handle->fetch($cache_key);

    state $req = sub ($h) {

        # $h->push_write(qq[AUTHENTICATE "$password"${CRLF}SIGNAL NEWNYM${CRLF}QUIT${CRLF}]);
        $h->push_write(qq[SIGNAL NEWNYM${CRLF}]);

        $h->store( $cache_key, 600 );

        return;
    };

    if ( !$h ) {
        $h = Pcore::AE::Handle->new(
            connect  => [ $self->host, $self->control_port ],
            on_error => sub ( $h, $fatal, $message ) {
                $h->destroy;

                return;
            },
            on_connect => sub (@) {
                my $password = $self->has_password ? $self->password : q[];

                $h->push_write(qq[AUTHENTICATE "$password"${CRLF}]);

                $req->($h);

                return;
            },
        );
    }
    else {
        $req->($h);
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy::Source::Tor

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
