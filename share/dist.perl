{   dist => {
        name             => 'Pcore',
        author           => 'zdm <zdm@cpan.org>',
        abstract         => 'Pcore - perl applications development environment',
        license          => 'Perl_5',
        copyright_holder => 'zdm',
        copyright_year   => '2015',
        main_module      => 'lib/Pcore.pm',
        cpan             => 1,                                                     # 1 - CPAN distribution
        ExecDir          => { dir => 'bin', },
    },

    # default global log channels
    log => [                                                                       #
        { level => '<=WARN', ns => q[*], channel => 'Console' },
        { level => 'FATAL',  ns => q[*], channel => 'File', stream => 'fatal.log' },
        { level => 'ERROR',  ns => q[*], channel => 'File', stream => 'error.log' },
        { level => 'WARN',   ns => q[*], channel => 'File', stream => 'warn.log' }
    ],

    util => {},
}
