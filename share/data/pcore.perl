{   cpanm => {    # known CPAN deps, that works, but tests are not passed during build
        'MSWin32-x86-multi-thread-64int' => [qw[Test::TCP]],
        'MSWin32-x64-multi-thread'       => [qw[Test::TCP]],
    },
    par_deps => [    # following packages will be added to any PAR automatically
    ],
    arch_deps => {
        'MSWin32-x86-multi-thread-64int' => {
            pkg => [    # default packages to include, eg: 'Win32/Unicode.pm'
            ],
            so => {
                'B/Hooks/OP/Check.pm'      => ['auto/B/Hooks/OP/Check/Check.xs.dll'],
                'Filter/Crypto/Decrypt.pm' => [ 'libeay32_.dll', 'zlib1_.dll' ],
                'Net/SSLeay.pm'            => [ 'ssleay32_.dll', 'libeay32_.dll', 'zlib1_.dll' ],
                'XML/Hash/XS.pm'           => [ 'libxml2-2_.dll', 'libiconv-2_.dll', 'zlib1_.dll' ],
                'XML/LibXML.pm'            => [ 'libxml2-2_.dll', 'libiconv-2_.dll', 'zlib1_.dll' ],
            },
        },
        'MSWin32-x64-multi-thread' => {
            pkg => [    # default packages to include, eg: 'Win32/Unicode.pm'
            ],
            so => {
                'B/Hooks/OP/Check.pm'      => ['auto/B/Hooks/OP/Check/Check.xs.dll'],
                'Filter/Crypto/Decrypt.pm' => [ 'libeay32__.dll', 'zlib1__.dll' ],
                'Net/SSLeay.pm'            => [ 'ssleay32__.dll', 'libeay32__.dll', 'zlib1__.dll' ],
                'XML/Hash/XS.pm'           => [ 'libxml2-2__.dll', 'libiconv-2__.dll', 'zlib1__.dll' ],
                'XML/LibXML.pm'            => [ 'libxml2-2__.dll', 'libiconv-2__.dll', 'zlib1__.dll' ],
            },
        },
    },
}
