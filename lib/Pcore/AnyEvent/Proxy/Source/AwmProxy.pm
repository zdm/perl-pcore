package Pcore::AnyEvent::Proxy::Source::AwmProxy;

use Pcore qw[-class];

with qw[Pcore::AnyEvent::Proxy::Source];

has api_key      => ( is => 'ro', isa => Str,         required  => 1 );
has username     => ( is => 'ro', isa => Str,         predicate => 1 );
has password     => ( is => 'ro', isa => Str,         predicate => 1 );
has http_timeout => ( is => 'ro', isa => PositiveInt, default   => 10 );

has '+max_threads' => ( isa => Enum [ 0, 350 ], default => 350 );
has '+is_multiproxy' => ( default => 1 );

no Pcore;

sub BUILD ( $self, $args ) {
    $self->bind_ip if $args->{bind_ip};

    return;
}

sub load ( $self, $cb ) {
    P->ua->request(
        'http://awmproxy.com/allproxy.php?full=1',
        timeout   => $self->http_timeout,
        on_finish => sub ($res) {
            my $proxies;

            if ( $res->status == 200 && $res->has_body ) {
                P->text->decode_eol( $res->body );

                for my $addr ( split /\n/sm, $res->body->$* ) {
                    my ( $addr, $real_ip, $country, $speed, $time ) = split /;/sm, $addr;

                    push $proxies->@*, q[//] . $addr . q[?http&connect&socks];
                }
            }

            $cb->($proxies);

            return;
        },
    );

    return;
}

sub bind_ip ($self) {
    die if !$self->has_username || !$self->has_password;

    P->ua->request( 'http://awmproxy.com/setmyip.php?Login=' . $self->username . '&Password=' . $self->password, blocking => 1 );

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
