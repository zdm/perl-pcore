{   cpan_notest => {    # following modules will be deployed without testing
        'MSWin32-x86-multi-thread-64int' => [qw[Test::TCP]],
        'MSWin32-x64-multi-thread'       => [qw[Test::TCP]],
    },
    par => {
        mod => [        # default modules, that will be added to each PAR

            # example:
            # 'bytes_heavy.pl',
            # 'HTTP/Date.pm',
        ],
        mod_ignore => [    # modules to ignore
            'Method/Generate/Accessor__WITH__Method/Generate/Accessor/Role/TypeTiny.pm',
            'Method/Generate/Accessor__WITH__Method/Generate/Accessor/Role/TypeTiny__WITH__Method/Generate/Accessor/Role/TypeTiny.pm',
        ],
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
