package Pcore::API::S3;

use Pcore -class;
use Pcore::Util::Digest qw[sha256_hex hmac_sha256 hmac_sha256_hex];

has key      => ();
has secret   => ();
has bucket   => ();
has region   => ();
has service  => 's3';
has endpoint => 'digitaloceanspaces.com';

sub _request ( $self, $method, @args ) {
    my %args = (
        bucket  => $self->{bucket},
        region  => $self->{region},
        path    => '/',
        params  => undef,
        headers => undef,
        data    => undef,
        @args,
    );

    my $date          = P->date->now_utc;
    my $date_ymd      = $date->strftime('%Y%m%d');
    my $date_iso08601 = $date->strftime('%Y%m%dT%H%M%SZ');
    my $host          = join '.', $args{bucket} // (), $args{region}, $self->{endpoint};
    my $params        = defined $args{params} ? P->data->to_uri( $args{params} ) : q[];
    my $data_hash     = sha256_hex( $args{data} ? $args{data}->$* : q[] );

    $args{headers}->{'Host'}                 = $host;
    $args{headers}->{'Date'}                 = $date->to_http_date;
    $args{headers}->{'X-Amz-Date'}           = $date_iso08601;
    $args{headers}->{'X-Amz-Content-Sha256'} = $data_hash if $data_hash;

    my $canon_req = "$method\n$args{path}\n$params\n";
    my @signed_headers;

    for my $header ( sort keys $args{headers}->%* ) {
        push @signed_headers, lc $header;

        $canon_req .= lc($header) . ":$args{headers}->{$header}\n";
    }

    my $signed_headers = join ';', @signed_headers;

    $canon_req .= "\n$signed_headers\n$data_hash";

    my $credential_scope = "$date_ymd/$args{region}/$self->{service}/aws4_request";
    my $string_to_sign   = "AWS4-HMAC-SHA256\n$date_iso08601\n$credential_scope\n" . sha256_hex $canon_req;

    my $k_date = hmac_sha256 $date_ymd, "AWS4$self->{secret}";
    my $k_region = hmac_sha256 $args{region}, $k_date;
    my $k_service = hmac_sha256 $self->{service}, $k_region;
    my $sign_key = hmac_sha256 'aws4_request', $k_service;
    my $signature = hmac_sha256_hex $string_to_sign, $sign_key;

    return P->http->request(
        method  => $method,
        url     => 'https://' . $host . ( $params ? "?$params" : q[] ),
        headers => [
            $args{headers}->%*,
            Referer       => undef,
            Authorization => qq[AWS4-HMAC-SHA256 Credential=$self->{key}/$credential_scope,SignedHeaders=$signed_headers,Signature=$signature],
        ],
        data => $args{data},
        sub ($res) {
            $res->{data} = P->data->from_xml( $res->{data} ) if $res;

            return $res;
        }
    );
}

sub get_buckets ( $self, @args ) {
    my %args = (
        region => $self->{region},
        @args
    );

    return $self->_request( 'GET', bucket => undef, %args );
}

sub get_bucket_content ( $self, @args ) {
    my %args = (
        bucket => $self->{bucket},
        region => $self->{region},
        @args
    );

    return $self->_request( 'GET', bucket => undef, %args );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    1 | 85                   | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::S3

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
