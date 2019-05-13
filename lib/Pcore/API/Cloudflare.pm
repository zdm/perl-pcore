package Pcore::API::Cloudflare;

use Pcore -const, -class, -res;

has email => ( required => 1 );
has key   => ( required => 1 );

has _headers => ( init_arg => undef );

const our $API_VER => 4;

sub _do_req ( $self, $method, $path, $query, $data, $cb ) {
    my $url = qq[https://api.cloudflare.com/client/v$API_VER/$path];

    $url .= '?' . P->data->to_uri($query) if defined $query;

    my $res = P->http->request(
        method  => $method,
        url     => $url,
        headers => $self->{_headers} //= [
            'X-Auth-Email' => $self->{email},
            'X-Auth-Key'   => $self->{key},
            'Content-Type' => 'application/json',
        ],
        data => defined $data ? P->data->to_json($data) : undef,
    );

    my $api_res;

    if ($res) {
        $api_res = res $res, P->data->from_json( $res->{data} );
    }
    else {
        $api_res = res $res;

        $api_res->{data} = P->data->from_json( $res->{data} ) if $res->{data};
    }

    return $api_res;
}

# https://api.cloudflare.com/#zone-list-zones
sub zones ( $self, $cb = undef ) {
    my $res = $self->_do_req( 'GET', '/zones', undef, undef, $cb );

    $res->{data} = { map { $_->{name} => $_ } $res->{data}->{result}->@* } if $res;

    return $res;
}

# https://api.cloudflare.com/#zone-create-zone
sub zone_create ( $self, $domain, $account_id, $cb = undef ) {
    my $res = $self->_do_req(
        'POST', '/zones', undef,
        {   name       => $domain,
            account    => { id => $account_id, },
            jump_start => \1,
            type       => 'full',
        },
        $cb
    );

    return $res;
}

# https://api.cloudflare.com/#zone-delete-zone
sub zone_remove ( $self, $id, $cb = undef ) {
    my $res = $self->_do_req( 'DELETE', "/zones/$id", undef, undef, $cb );

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 12                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Cloudflare

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
