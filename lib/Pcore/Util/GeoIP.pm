package Pcore::Util::GeoIP;

use Pcore qw[-autoload];
use Const::Fast qw[const];

const our $GEOIP_STANDARD     => 0;    # PP
const our $GEOIP_MEMORY_CACHE => 1;    # PP
const our $GEOIP_CHECK_CACHE  => 2;    # when using memory cache you can force a reload if the file is updated by setting GEOIP_CHECK_CACHE
const our $GEOIP_INDEX_CACHE  => 4;    # caches the most frequently accessed index portion of the database, resulting in faster lookups than GEOIP_STANDARD, but less memory usage than GEOIP_MEMORY_CACHE - useful for larger databases such as GeoIP Legacy Organization and GeoIP City. Note, for GeoIP Country, Region and Netspeed databases, GEOIP_INDEX_CACHE is equivalent to GEOIP_MEMORY_CACHE

const our $TYPE_CITY       => 1;
const our $TYPE_CITY_V6    => 2;
const our $TYPE_COUNTRY    => 3;
const our $TYPE_COUNTRY_V6 => 4;

our $GEOIP_PURE_PERL          = 0;                     # force to use pure perl mode
our $GEOIP_COUNTRY_CACHE_MODE = $GEOIP_MEMORY_CACHE;
our $GEOIP_CITY_CACHE_MODE    = $GEOIP_INDEX_CACHE;

my $H;

sub country_path ( $self, $force = undef, $cv = undef ) {
    state $path = do {
        my $_path = P->res->get_local('geoip_country.dat');

        if ( !$_path || $force ) {
            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz',
                buf_size    => 1,
                on_progress => $cv ? 1 : 0,
                blocking => $cv || 1,
                on_finish => sub ($res) {
                    require IO::Uncompress::Gunzip;

                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile( autoflush => 1 );

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $_path = P->res->store_local( 'geoip_country.dat', $temp->path );
                    }

                    return;
                }
            );
        }

        $_path;
    };

    return $path;
}

sub country_v6_path ( $self, $force = undef, $cv = undef ) {
    state $path = do {
        my $_path = P->res->get_local('geoip_country_v6.dat');

        if ( !$_path || $force ) {
            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoIPv6.dat.gz',
                buf_size    => 1,
                on_progress => $cv ? 1 : 0,
                blocking => $cv || 1,
                on_finish => sub ($res) {
                    require IO::Uncompress::Gunzip;

                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile( autoflush => 1 );

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp, BinModeOut => 1 );

                        $_path = P->res->store_local( 'geoip_country_v6.dat', $temp->path );
                    }

                    return;
                }
            );
        }

        $_path;
    };

    return $path;
}

sub city_path ( $self, $force = undef, $cv = undef ) {
    state $path = do {
        my $_path = P->res->get_local('geoip_city.dat');

        if ( !$_path || $force ) {
            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz',
                buf_size    => 1,
                on_progress => $cv ? 1 : 0,
                blocking => $cv || 1,
                on_finish => sub ($res) {
                    require IO::Uncompress::Gunzip;

                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile( autoflush => 1 );

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $_path = P->res->store_local( 'geoip_city.dat', $temp->path );
                    }

                    return;
                }
            );
        }

        $_path;
    };

    return $path;
}

sub city_v6_path ( $self, $force = undef, $cv = undef ) {
    state $path = do {
        my $_path = P->res->get_local('geoip_city_v6.dat');

        if ( !$_path || $force ) {
            P->ua->request(
                'https://geolite.maxmind.com/download/geoip/database/GeoLiteCityv6-beta/GeoLiteCityv6.dat.gz',
                buf_size    => 1,
                on_progress => $cv ? 1 : 0,
                blocking => $cv || 1,
                on_finish => sub ($res) {
                    require IO::Uncompress::Gunzip;

                    if ( $res->status == 200 ) {
                        my $temp = P->file->tempfile( autoflush => 1 );

                        IO::Uncompress::Gunzip::gunzip( $res->body, $temp->path, BinModeOut => 1 );

                        $_path = P->res->store_local( 'geoip_city_v6.dat', $temp->path );
                    }

                    return;
                }
            );
        }

        $_path;
    };

    return $path;
}

sub _get_h ( $self, $type ) {
    if ( !defined $H->{$type} ) {
        my $db_path;

        my $default_cache_mode;

        my $use_pure_perl = $GEOIP_PURE_PERL;

        if ($use_pure_perl) {
            require Geo::IP::PurePerl;    ## no critic qw[Modules::ProhibitEvilModules]
        }
        else {
            $use_pure_perl = try {
                require Geo::IP;          ## no critic qw[Modules::ProhibitEvilModules]

                return 0;
            }
            catch {
                require Geo::IP::PurePerl;    ## no critic qw[Modules::ProhibitEvilModules]

                return 1;
            };
        }

        if ( $type == $TYPE_COUNTRY ) {
            $db_path = $self->country_path;

            $default_cache_mode = $GEOIP_COUNTRY_CACHE_MODE;
        }
        elsif ( $type == $TYPE_COUNTRY_V6 ) {
            $db_path = $self->country_path_v6;

            $default_cache_mode = $GEOIP_COUNTRY_CACHE_MODE;
        }
        elsif ( $type == $TYPE_CITY ) {
            $db_path = $self->city_path;

            $default_cache_mode = $GEOIP_CITY_CACHE_MODE;
        }
        elsif ( $type == $TYPE_CITY_V6 ) {
            $db_path = $self->city_path_v6;

            $default_cache_mode = $GEOIP_CITY_CACHE_MODE;
        }

        # use $GEOIP_MEMORY_CACHE instead of $GEOIP_INDEX_CACHE if $GEOIP_INDEX_CACHE is not supported
        my $flags = $use_pure_perl && $default_cache_mode == $GEOIP_INDEX_CACHE ? $GEOIP_MEMORY_CACHE : $default_cache_mode;

        $flags = $flags | $GEOIP_CHECK_CACHE if !$use_pure_perl;

        my $class = $use_pure_perl ? 'Geo::IP::PurePerl' : 'Geo::IP';

        $H->{$type} = $class->open( $db_path, $flags );
    }

    return $H->{$type};
}

sub reconnect ($self) {
    undef $H;

    return;
}

sub update ($self) {
    $H = undef;

    my $cv = AE::cv;

    $self->country_path( 1, $cv );

    $self->country_v6_path( 1, $cv );

    $self->city_path( 1, $cv );

    $self->city_v6_path( 1, $cv );

    $cv->recv;

    # $self->_connect;

    return;
}

sub autoload {
    my $self   = shift;
    my $method = shift;

    return sub {
        my $self = shift;

        return $self->_get_h($TYPE_COUNTRY)->$method(@_);
    };
}

# city methods
sub record_by_addr {
    my $self = shift;

    return $self->_get_h($TYPE_CITY)->record_by_addr(@_);
}

sub record_by_name {
    my $self = shift;

    return $self->_get_h($TYPE_CITY)->record_by_name(@_);
}

1;
__END__
