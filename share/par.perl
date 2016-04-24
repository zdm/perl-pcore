{
    # shared resources, used by modules in this distribution
    mod_share => {
        'Pcore/Dist/Build/Deploy.pm' => ['/data/pcore.perl'],
        'Pcore/Dist/Build/PAR'       => ['/data/pcore.perl'],
        'Pcore/Src/File.pm'          => ['/data/src.perl'],
        'Pcore/Util/Path.pm'         => ['/data/mime.perl'],
        'Pcore/Util/URI/Host.pm'     => [ '/data/pub_suffix.dat', '/data/tld.dat' ],
        'Pcore/Util/URI/Web2.pm'     => ['/data/web2.perl'],
    },

    # scripts
    script => {},
}
