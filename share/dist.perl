{   dist => {
        name             => 'Pcore',
        author           => 'zdm <zdm@cpan.org>',
        license          => 'Perl_5',
        copyright_holder => 'zdm',
        cpan             => 1,                      # CPAN distribution
        cpan_bin         => 1,                      # upload bin to CPAN
        util             => {},
    },

    # default log channels
    log => [                                        #
        [ 'fatal', 'stderr:', 'file:fatal.log' ],
        [ 'error', 'stderr:', 'file:error.log' ],
        [ 'warn',  'stderr:', 'file:warn.log' ],
    ],
}
