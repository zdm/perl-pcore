package Pcore::Handle::Jabber;

use Pcore -class;

with qw[Pcore::Core::H::Role::Wrapper];

has driver => ( is => 'rw', isa => Enum [ 'Jabber::Connection', 'Net::XMPP' ], default => 'Jabber::Connection' );

# PHARAOH_JABBER_SOFTVISIO_NET => {
#    DRV        => 'jabber',
#    SERVER     => 'jabber.softvisio.net:5222',
#    USER       => 'pharaoh',
#    AUTH       => 'DjMq1mc68vTnlO4T',
#    RESOURCE   => '\'pharaoh@jabber.softvisio.net\' <pharaoh@jabber.softvisio.net>',
#    COMPONENT  => 'jabber.softvisio.net',
#    CONNECTION => 'tcpip',
#    TLS        => 1,
# };

# H
sub h_connect {
    my $self = shift;

    my $h;

    if ( $self->driver eq ' Jabber::Connection ' ) {
        require Jabber::Connection;

        $h = Jabber::Connection->new(
            server => $PROC->{CFG}->{H}->{ $self->name }->{SERVER},
            log    => 0,
            ssl    => 1,
        );

        die 'Jabber: ' . $h->lastError unless $h->connect;

        try {
            $h->auth( $PROC->{CFG}->{H}->{ $self->name }->{USER}, $PROC->{CFG}->{H}->{ $self->name }->{AUTH}, $PROC->{CFG}->{H}->{ $self->name }->{RESOURCE} );
        }
        catch {
            my $e = shift;
            die ' Jabber : Authorization error !';
        };
    }
    else {
        require Net::XMPP;

        $h = Net::XMPP::Client->new(
            debuglevel => 0,
            debugfile  => ' stdout ',
        );

        my ( $host, $port ) = $PROC->{CFG}->{H}->{ $self->name }->{SERVER} =~ /\A(.+?):(\d+)\z/sm;
        $port ||= 5222;
        my $status = $h->Connect(
            hostname       => $host,
            port           => $port,
            componentname  => $PROC->{CFG}->{H}->{ $self->name }->{COMPONENT},    # mandatory and needed only for gmail, domain part of JID
            connectiontype => $PROC->{CFG}->{H}->{ $self->name }->{CONNECTION},
            tls            => $PROC->{CFG}->{H}->{ $self->name }->{TLS},
        );
        die ' Jabber : Connection error !' unless $h->Connected;

        my @result = try {
            return $h->AuthSend(
                username => $PROC->{CFG}->{H}->{ $self->name }->{USER},
                password => $PROC->{CFG}->{H}->{ $self->name }->{AUTH},
                resource => $PROC->{CFG}->{H}->{ $self->name }->{RESOURCE},
            );
        }
        catch {
            die ' Jabber : Authorization error !' if $result[0] ne ' ok ';
        };
    }

    return $h;
}

sub h_disconnect {
    my $self = shift;

    $self->h->disconnect if ref $self->h eq ' Jabber::Connection ';
    $self->h->Disconnect if ref $self->h eq ' Net::XMPP::Client ';

    return;
}

# JABBER
sub send_message {
    my $self    = shift;
    my %options = @_;

    if ( ref $self->h eq ' Jabber::Connection ' ) {
        my $message = ref $options{message} ? ${ $options{message} } : $options{message};
        P->text->encode_utf8($message);
        my $msg = $self->h->{nf}->newNode(' message ');
        $msg->insertTag(' body ')->data($message);
        $msg->attr( ' to ', ref $options{to} ? ${ $options{to} } : $options{to} );
        $self->h->send($msg);
    }
    elsif ( ref $self->h eq ' Net::XMPP::Client ' ) {
        $self->h->MessageSend( to => ref $options{to} ? ${ $options{to} } : $options{to}, body => ref $options{message} ? ${ $options{message} } : $options{message} );
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NOTES

=head2 Net::XMPP

=over

=item * Support SSL;

=item * Works on all account types;

=item * WARNING!!! Don' t install Authen::SASL::XS - this lead to authorization problems;

=item * WARNING!!! Connected driver takes about 10M RAM;

=back

=head2 Jabber::Connection

=over

=item * Small and lightweight;

=item * Don't support SSL yet, connection is unsecure;

=item * Don't work on GTalk accounts;

=back

=head1 WARNINGS

=over

=item * All drivers confirmed memory leaks on reconnect;

=item * All drivers couldn't detect if server disaonnected. In this case messages will be lost;

=back

=cut
