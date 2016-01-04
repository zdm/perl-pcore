{   cpan_notest => {    # following modules will be deployed without testing
        'MSWin32-x86-multi-thread-64int' => [qw[Test::TCP]],
        'MSWin32-x64-multi-thread'       => [qw[Test::TCP]],
    },
    par => {
        mod => [        #
            'bytes_heavy.pl',
            'HTTP/Date.pm',
            'Pcore/Core/H/Role.pm',
            'Pcore/Core/H/Role/Wrapper.pm',
            'Pcore/Handle/File.pm',
            'Pcore/Util/Date.pm',
            'Pcore/Util/Sys.pm',
            'Time/Local.pm',
            'Time/Moment.pm',
            'Time/Zone.pm',
        ],
        mod_resource => {
            'Pcore/Dist/Build/Deploy.pm' => ['/data/pcore.perl'],
            'Pcore/Dist/Build/PAR'       => ['/data/pcore.perl'],
            'Pcore/Src/File.pm'          => ['/data/src.perl'],
            'Pcore/Util/GeoIP.pm'        => [                       #
                '/data/geoip_country.dat',
                '/data/geoip_country_v6.dat',
                '/data/geoip2_country.dat',
                '/data/geoip_city.dat',
                '/data/geoip_city_v6.dat',
                '/data/geoip2_city.dat',
            ],
            'Pcore/Util/Path.pm'     => ['/data/mime.perl'],
            'Pcore/Util/URI/Host.pm' => [ '/data/pub_suffix.dat', '/data/tld.dat' ],
            'Pcore/Util/URI/Web2.pm' => ['/data/web2.perl'],
        },
        arch => {
            'MSWin32-x86-multi-thread-64int' => {
                mod       => [],
                mod_shlib => {
                    'B/Hooks/OP/Check.pm'       => ['auto/B/Hooks/OP/Check/Check.xs.dll'],
                    'Filter/Crypto/Decrypt.pm'  => [ 'libeay32_.dll', 'zlib1_.dll' ],
                    'Net/SSLeay.pm'             => [ 'ssleay32_.dll', 'libeay32_.dll', 'zlib1_.dll' ],
                    'Pcore/Util/PM/RPC/Proc.pm' => [$^X],
                    'XML/Hash/XS.pm'            => [ 'libxml2-2_.dll', 'libiconv-2_.dll', 'zlib1_.dll' ],
                    'XML/LibXML.pm'             => [ 'libxml2-2_.dll', 'libiconv-2_.dll', 'zlib1_.dll' ],
                },
            },
            'MSWin32-x64-multi-thread' => {
                mod       => [],
                mod_shlib => {
                    'B/Hooks/OP/Check.pm'       => ['auto/B/Hooks/OP/Check/Check.xs.dll'],
                    'Filter/Crypto/Decrypt.pm'  => [ 'libeay32__.dll', 'zlib1__.dll' ],
                    'Net/SSLeay.pm'             => [ 'ssleay32__.dll', 'libeay32__.dll', 'zlib1__.dll' ],
                    'Pcore/Util/PM/RPC/Proc.pm' => [$^X],
                    'XML/Hash/XS.pm'            => [ 'libxml2-2__.dll', 'libiconv-2__.dll', 'zlib1__.dll' ],
                    'XML/LibXML.pm'             => [ 'libxml2-2__.dll', 'libiconv-2__.dll', 'zlib1__.dll' ],
                },
            },
        },
    },
};
