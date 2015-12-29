package Pcore::API::Majestic;

use Pcore -class;

has api_key              => ( is => 'ro',   isa => Str );
has openapp_key          => ( is => 'ro',   isa => Str );
has openapp_access_token => ( is => 'ro',   isa => Str );
has failover             => ( is => 'lazy', isa => Bool, default => 0 );
has datasource           => ( is => 'lazy', isa => Enum [qw[historic fresh]], default => 'fresh' );

no Pcore;

sub get_index_item_info ( $self, $domains, $cb ) {
    die q[Maximum items number is 100] if $domains->@* > 100;

    my $url_params = {
        cmd                        => 'GetIndexItemInfo',
        datasource                 => $self->datasource,
        EnableResourceUnitFailover => $self->failover,
        items                      => scalar $domains->@*,
    };

    if ( $self->api_key ) {
        $url_params->{app_api_key} = $self->api_key;
    }
    elsif ( $self->openapp_key && $self->openapp_access_token ) {
        $url_params->{privatekey} = $self->openapp_key;

        $url_params->{accesstoken} = $self->openapp_access_token;
    }
    else {
        die q["app_api_key" or "openapp_key" and "openapp_access_token" are missed];
    }

    for my $i ( 0 .. $domains->$#* ) {
        $url_params->{ 'item' . $i } = $domains->[$i];
    }

    my $url = q[http://api.majestic.com/api/json?] . P->data->to_uri($url_params);

    P->http->get(
        $url,
        on_finish => sub ($res) {
            if ( $res->status == 200 ) {
                my $json = P->data->decode( $res->body );

                $cb->($json);
            }
            else {
                $cb->();
            }

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

Pcore::API::Majestic

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
