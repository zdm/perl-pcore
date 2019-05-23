package Pcore::API::Facebook;

use Pcore -class, -res;

with qw[Pcore::API::Facebook::User Pcore::API::Facebook::Marketing];

has token => ( required => 1 );

sub _req ( $self, $method, $path, $params, $data, $cb = undef ) {
    my $url = "https://graph.facebook.com/$path?access_token=$self->{token}";

    $url .= '&' . P->data->to_uri($params) if $params;

    return P->http->request(
        method => $method,
        url    => $url,
        data   => $data,
        sub ($res) {
            my $api_res = res 200, P->data->from_json( $res->{data} );

            return $cb ? $cb->($api_res) : $api_res;
        }
    );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 9                    | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 9                    | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_req' declared but not used         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Facebook

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
