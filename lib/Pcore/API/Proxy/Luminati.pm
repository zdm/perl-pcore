package Pcore::API::Proxy::Luminati;

use Pcore -class;
use Pcore::Util::UUID qw[uuid_v1mc_hex];

has host     => 'zproxy.lum-superproxy.io';
has port     => ( required => 1 );
has username => ( required => 1 );
has password => ( required => 1 );
has zone     => ( required => 1 );

has country => ();

sub get_proxy ( $self, $country = undef ) {
    $country //= $self->{country};

    my $proxy = "lum-customer-$self->{username}-zone-$self->{zone}";

    $proxy .= "-country-$country" if $country;

    $proxy .= ":$self->{password}\@$self->{host}:$self->{port}";

    return $proxy;
}

# TODO get host
sub get_proxy_session ( $self, $country = undef ) {
    $country //= $self->{country};

    my $proxy = "lum-customer-$self->{username}-zone-$self->{zone}";

    $proxy .= "-country-$country" if $country;

    $proxy .= '-session-' . uuid_v1mc_hex;

    $proxy .= ":$self->{password}\@$self->{host}:$self->{port}";

    return $proxy;
}

sub restore_proxy_session ( $self, $host, $session ) {
    my $proxy = "connect://lum-customer-$self->{username}-zone-$self->{zone}";

    # $proxy .= "-country-$country" if $country;

    $proxy .= "-session-$session";

    $proxy .= ":$self->{password}\@$host:$self->{port}";

    return $proxy;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Proxy::Luminati

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
