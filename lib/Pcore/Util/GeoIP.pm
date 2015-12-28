package Pcore::Util::GeoIP;

use Pcore -const;

const our $GEOIP_STANDARD     => 0;    # PP
const our $GEOIP_MEMORY_CACHE => 1;    # PP
const our $GEOIP_CHECK_CACHE  => 2;    # when using memory cache you can force a reload if the file is updated by setting GEOIP_CHECK_CACHE
const our $GEOIP_INDEX_CACHE  => 4;    # caches the most frequently accessed index portion of the database, resulting in faster lookups than GEOIP_STANDARD, but less memory usage than GEOIP_MEMORY_CACHE - useful for larger databases such as GeoIP Legacy Organization and GeoIP City. Note, for GeoIP Country, Region and Netspeed databases, GEOIP_INDEX_CACHE is equivalent to GEOIP_MEMORY_CACHE

const our $TYPE_COUNTRY    => 1;
const our $TYPE_COUNTRY_V6 => 2;
const our $TYPE_COUNTRY2   => 3;
const our $TYPE_CITY       => 4;
const our $TYPE_CITY_V6    => 5;
const our $TYPE_CITY2      => 5;

our $GEOIP_PURE_PERL          = 0;                     # force to use pure perl mode
our $GEOIP_COUNTRY_CACHE_MODE = $GEOIP_MEMORY_CACHE;
our $GEOIP_CITY_CACHE_MODE    = $GEOIP_INDEX_CACHE;

my $H;

sub clear {
    undef $H;

    return;
}

sub update {
    clear();

    my $cv = AE::cv;

    country($cv);

    country_v6($cv);

    country2($cv);

    city($cv);

    city_v6($cv);

    city2($cv);

    $cv->recv;

    return;
}

sub country ($update = undef) {
    if ( !exists $H->{$TYPE_COUNTRY} || $update ) {
        if ($update) {
            state $init = !!require IO::Uncompress::Gunzip;

            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz',
                buf_size    => 1,
                on_progress => 1,
                blocking    => $update,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile;

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $ENV->res->store( $temp->path, '/data/geoip_country.dat', 'pcore' );
                    }

                    return;
                }
            );
        }

        my $path = $ENV->res->get('/data/geoip_country.dat');

        return if !$path;

        $H->{$TYPE_COUNTRY} = _get_h( $TYPE_COUNTRY, $path );
    }

    return $H->{$TYPE_COUNTRY};
}

sub country_v6 ($update = undef) {
    if ( !exists $H->{$TYPE_COUNTRY_V6} || $update ) {
        if ($update) {
            state $init = !!require IO::Uncompress::Gunzip;

            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoIPv6.dat.gz',
                buf_size    => 1,
                on_progress => 1,
                blocking    => $update,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile;

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $ENV->res->store( $temp->path, '/data/geoip_country_v6.dat', 'pcore' );
                    }

                    return;
                }
            );
        }

        my $path = $ENV->res->get('/data/geoip_country_v6.dat');

        return if !$path;

        $H->{$TYPE_COUNTRY_V6} = _get_h( $TYPE_COUNTRY_V6, $path );
    }

    return $H->{$TYPE_COUNTRY_V6};
}

sub country2 ($update = undef) {
    if ( !exists $H->{$TYPE_COUNTRY2} || $update ) {
        if ($update) {
            state $init = !!require IO::Uncompress::Gunzip;

            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.mmdb.gz',
                buf_size    => 1,
                on_progress => 1,
                blocking    => $update,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile;

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $ENV->res->store( $temp->path, '/data/geoip2_country.dat', 'pcore' );
                    }

                    return;
                }
            );
        }

        my $path = $ENV->res->get('/data/geoip2_country.dat');

        return if !$path;

        # $H->{$TYPE_COUNTRY2} = _get_h( $TYPE_COUNTRY2, $path );
    }

    return $H->{$TYPE_COUNTRY2};
}

sub city ($update = undef) {
    if ( !exists $H->{$TYPE_CITY} || $update ) {
        if ($update) {
            state $init = !!require IO::Uncompress::Gunzip;

            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz',
                buf_size    => 1,
                on_progress => 1,
                blocking    => $update,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile;

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $ENV->res->store( $temp->path, '/data/geoip_city.dat', 'pcore' );
                    }

                    return;
                }
            );
        }

        my $path = $ENV->res->get('/data/geoip_city.dat');

        return if !$path;

        $H->{$TYPE_CITY} = _get_h( $TYPE_CITY, $path );
    }

    return $H->{$TYPE_CITY};
}

sub city_v6 ($update = undef) {
    if ( !exists $H->{$TYPE_CITY_V6} || $update ) {
        if ($update) {
            state $init = !!require IO::Uncompress::Gunzip;

            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoLiteCityv6-beta/GeoLiteCityv6.dat.gz',
                buf_size    => 1,
                on_progress => 1,
                blocking    => $update,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile;

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $ENV->res->store( $temp->path, '/data/geoip_city_v6.dat', 'pcore' );
                    }

                    return;
                }
            );
        }

        my $path = $ENV->res->get('/data/geoip_city_v6.dat');

        return if !$path;

        $H->{$TYPE_CITY_V6} = _get_h( $TYPE_CITY_V6, $path );
    }

    return $H->{$TYPE_CITY_V6};
}

sub city2 ($update = undef) {
    if ( !exists $H->{$TYPE_CITY2} || $update ) {
        if ($update) {
            state $init = !!require IO::Uncompress::Gunzip;

            P->ua->request(
                'http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz',
                buf_size    => 1,
                on_progress => 1,
                blocking    => $update,
                on_finish   => sub ($res) {
                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile;

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $ENV->res->store( $temp->path, '/data/geoip_city2.dat', 'pcore' );
                    }

                    return;
                }
            );
        }

        my $path = $ENV->res->get('/data/geoip_city2.dat');

        return if !$path;

        # $H->{$TYPE_CITY2} = _get_h( $TYPE_CITY2, $path );
    }

    return $H->{$TYPE_CITY2};
}

sub _get_h ( $type, $path ) {
    my $default_cache_mode;

    my $use_pure_perl = $GEOIP_PURE_PERL;

    if ($use_pure_perl) {
        state $init = !!require Geo::IP::PurePerl;
    }
    else {
        $use_pure_perl = try {
            state $init = !!require Geo::IP;

            return 0;
        }
        catch {
            state $init = !!require Geo::IP::PurePerl;

            return 1;
        };
    }

    if ( $type == $TYPE_COUNTRY ) {
        $default_cache_mode = $GEOIP_COUNTRY_CACHE_MODE;
    }
    elsif ( $type == $TYPE_COUNTRY_V6 ) {
        $default_cache_mode = $GEOIP_COUNTRY_CACHE_MODE;
    }
    elsif ( $type == $TYPE_CITY ) {
        $default_cache_mode = $GEOIP_CITY_CACHE_MODE;
    }
    elsif ( $type == $TYPE_CITY_V6 ) {
        $default_cache_mode = $GEOIP_CITY_CACHE_MODE;
    }

    # use $GEOIP_MEMORY_CACHE instead of $GEOIP_INDEX_CACHE if $GEOIP_INDEX_CACHE is not supported
    my $flags = $use_pure_perl && $default_cache_mode == $GEOIP_INDEX_CACHE ? $GEOIP_MEMORY_CACHE : $default_cache_mode;

    $flags = $flags | $GEOIP_CHECK_CACHE if !$use_pure_perl;

    my $class = $use_pure_perl ? 'Geo::IP::PurePerl' : 'Geo::IP';

    return $class->open( $path, $flags );
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
