{   dist => {
        name             => 'Pcore',
        author           => 'zdm <zdm@cpan.org>',
        license          => 'Perl_5',
        copyright_holder => 'zdm',
        cpan             => 1,                      # CPAN distribution
        cpan_bin         => 1,                      # upload bin to CPAN
        mod_share        => {
            'Pcore/Dist/Build/Deploy.pm' => ['/data/pcore.perl'],
            'Pcore/Dist/Build/PAR'       => ['/data/pcore.perl'],
            'Pcore/Src/File.pm'          => ['/data/src.perl'],
            'Pcore/Util/Path.pm'         => ['/data/mime.perl'],
            'Pcore/Util/URI/Host.pm'     => [ '/data/pub_suffix.dat', '/data/tld.dat' ],
            'Pcore/Util/URI/Web2.pm'     => ['/data/web2.perl'],
        },
        util => {},
    },

    # default log channels
    log => [    #
        [ 'fatal', 'stderr:', 'file:fatal.log' ],
        [ 'error', 'stderr:', 'file:error.log' ],
        [ 'warn',  'stderr:', 'file:warn.log' ],
    ],
}
