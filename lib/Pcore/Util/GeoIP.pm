package Pcore::Util::GeoIP;

use Pcore -const, -res;

const our $TYPE_COUNTRY => 1;
const our $TYPE_CITY    => 2;

const our $RES => {
    $TYPE_COUNTRY => [    #
        "$ENV->{PCORE_USER_BUILD_DIR}/geolite2-country.mmdb",
        'https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&suffix=gz&license_key='
    ],
    $TYPE_CITY => [       #
        "$ENV->{PCORE_USER_BUILD_DIR}/geolite2-city.mmdb",
        'https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&suffix=gz&license_key='
    ],
};

my $LICENSE_KEY;
my $H;

sub set_license_key ($key) {
    $LICENSE_KEY = $key;

    return;
}

sub clear {
    undef $H;

    return;
}

sub update_all {
    my $res = update_country_db();

    return $res if !$res;

    $res = update_city_db();

    return $res;
}

sub update_country_db {
    print 'updating geolite2-country.mmdb ... ';

    my $res = _update($TYPE_COUNTRY);

    say $res;

    return $res;
}

sub update_city_db {
    print 'updating geolite2-city.mmdb ... ';

    my $res = _update($TYPE_CITY);

    say $res;

    return $res;
}

sub _update ( $type ) {
    require IO::Uncompress::Gunzip;

    my $license_key = $LICENSE_KEY || $ENV->user_cfg->{GEOIP_LICENSE_KEY};

    return res [ 200, 'No license key specified' ] if !$license_key;

    my $url = "$RES->{$type}->[1]$license_key";

    my $res = P->http->get(
        $url,
        mem_buf_size => 0,

        # on_progress  => 1
    );

    if ($res) {
        my $temp = P->file1->tempfile;

        IO::Uncompress::Gunzip::gunzip( $res->{data}->{path}, $temp->{path}, BinModeOut => 1 ) or return res [ 500, "gunzip failed: $IO::Uncompress::Gunzip::GunzipError" ];

        P->file->write_bin( $RES->{$type}->[0], $temp );

        # empty cache
        delete $H->{$type};

        return res 200;
    }

    return res $res;
}

sub country {
    _get_h($TYPE_COUNTRY) if !exists $H->{$TYPE_COUNTRY};

    return $H->{$TYPE_COUNTRY};
}

sub city {
    _get_h($TYPE_CITY) if !exists $H->{$TYPE_CITY};

    return $H->{$TYPE_CITY};
}

sub _get_h ($type) {
    my $path = $RES->{$type}->[0];

    return if !$path;

    require MaxMind::DB::Reader;

    $H->{$type} = MaxMind::DB::Reader->new( file => $path );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::GeoIP - Maxmind GeoIP wrapper

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
