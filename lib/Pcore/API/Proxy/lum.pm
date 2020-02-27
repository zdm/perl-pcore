package Pcore::API::Proxy::lum;

use Pcore -const, -class;
use Pcore::Util::UUID qw[uuid_v1mc_hex];
use AnyEvent::DNS;

with qw[Pcore::API::Proxy];

has is_http => 1;

has _parsed => ();

const our $DEFAULT_HOST => 'zproxy.lum-superproxy.io';
const our $DEFAULT_PORT => 22225;

around new => sub ( $orig, $self, $uri ) {
    $self = $self->$orig;

    $self->{uri} = $uri;

    return $self;
};

sub new_ip ( $self, %args ) {
    my $parsed = $self->{parsed} //= do {
        my $data;

        my $username = $self->{uri}->{username};

        while ( $username =~ /(lum-customer|zone|session|country)-([^-]+)/smg ) {
            $data->{$1} = $2;
        }

        $data;
    };

    my $uri = "lum://lum-customer-$parsed->{'lum-customer'}-zone-$parsed->{zone}";

    my $host = $self->{uri}->{host};

    if ( my $country = $args{country} || $parsed->{country} ) {
        $uri .= "-country-$country";
    }

    if ( $args{session} ) {
        $host = $self->_get_session_host($host);

        $uri .= "-session-" . uuid_v1mc_hex;
    }

    $uri .= ":$self->{uri}->{password}\@$host:$self->{uri}->{port}";

    $uri = P->uri($uri);

    return $self->new($uri);
}

sub _get_session_host ( $self, $host ) {
    AnyEvent::DNS::a $host, my $cv = P->cv;

    my @ip = $cv->recv;

    return $ip[0] || $host;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 48                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 14                   | ValuesAndExpressions::RequireNumberSeparators - Long number not separated with underscores                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Proxy::lum

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
