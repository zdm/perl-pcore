{   dist => {
        name             => 'Pcore',
        author           => 'zdm <zdm@cpan.org>',
        license          => 'Perl_5',
        copyright_holder => 'zdm',
        cpan             => 1,                      # CPAN distribution
        cpan_bin         => 1,                      # upload bin to CPAN
    },

    # default global log channels
    log => [                                        #
        { level => '<=WARN', ns => q[*], channel => 'Console' },
        { level => 'FATAL',  ns => q[*], channel => 'File', stream => 'fatal.log' },
        { level => 'ERROR',  ns => q[*], channel => 'File', stream => 'error.log' },
        { level => 'WARN',   ns => q[*], channel => 'File', stream => 'warn.log' }
    ],
}
