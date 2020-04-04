package Pcore::Util::GeoIP;

use Pcore -const, -res;

const our $TYPE_COUNTRY_LITE => 0;
const our $TYPE_CITY_LITE    => 1;

const our $BASE_PATH => $ENV->{PCORE_USER_BUILD_DIR};

const our $TYPE => {
    $TYPE_COUNTRY_LITE => 'GeoLite2-Country',
    $TYPE_CITY_LITE    => 'GeoLite2-City',
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
    print "updating $TYPE->{$TYPE_COUNTRY_LITE}.mmdb ... ";

    my $res = _update($TYPE_COUNTRY_LITE);

    say $res;

    return $res;
}

sub update_city_db {
    print "updating $TYPE->{$TYPE_CITY_LITE}.mmdb ... ";

    my $res = _update($TYPE_CITY_LITE);

    say $res;

    return $res;
}

sub _update ( $type ) {
    require Archive::Tar;

    my $license_key = $LICENSE_KEY || $ENV->user_cfg->{GEOIP_LICENSE_KEY};

    return res [ 200, 'No license key specified' ] if !$license_key;

    my $name = $TYPE->{$type};

    my $url = "https://download.maxmind.com/app/geoip_download?edition_id=$name&suffix=tar.gz&license_key=$license_key";

    my $res = P->http->get(
        $url,
        mem_buf_size => 0,

        # on_progress  => 1
    );

    return res $res if !$res;

    my $tar = eval { Archive::Tar->new( $res->{data}->{path} ) };

    return res [ 500, 'Unable to read tar' ] if $@;

    my @files = $tar->list_files;

    my $path;

    for my $file (@files) {
        if ( $file =~ /${name}_\d+\/${name}[.]mmdb/sm ) {
            $path = $file;

            last;
        }
    }

    return res [ 500, 'Unable to find mmdb file' ] if !$path;

    eval { $tar->extract_file( $path, "$BASE_PATH/$name.mmdb" ) };

    return res [ 500, 'Unable to extract mmdb file' ] if $@;

    # empty cache
    delete $H->{$type};

    return res 200;
}

sub country {
    return $H->{$TYPE_COUNTRY_LITE} //= _get_reader($TYPE_COUNTRY_LITE);
}

sub city {
    return $H->{$TYPE_CITY_LITE} //= _get_reader($TYPE_CITY_LITE);
}

sub _get_reader ($type) {
    my $path = "$BASE_PATH/$TYPE->{$type}.mmdb";

    return if !$path;

    require MaxMind::DB::Reader;

    return MaxMind::DB::Reader->new( file => $path );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 98                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
