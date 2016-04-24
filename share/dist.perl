{   dist => {
        name             => 'Pcore',
        author           => 'zdm <zdm@cpan.org>',
        license          => 'Perl_5',
        copyright_holder => 'zdm',
        cpan             => 1,                      # CPAN distribution
        cpan_bin         => 1,                      # upload bin to CPAN
    },

    # Pcore utils, provided by this distribution
    util => {

        # eg.:
        # util_accessor_name => 'Util::Package::Name'
        # and later in the code you can use P->util_accessor_name->...
    },

    # shared resources, used by modules in this distribution
    mod_share => {
        'Pcore/Dist/Build/Deploy.pm' => ['/data/pcore.perl'],
        'Pcore/Dist/Build/PAR'       => ['/data/pcore.perl'],
        'Pcore/Src/File.pm'          => ['/data/src.perl'],
        'Pcore/Util/Path.pm'         => ['/data/mime.perl'],
        'Pcore/Util/URI/Host.pm'     => [ '/data/pub_suffix.dat', '/data/tld.dat' ],
        'Pcore/Util/URI/Web2.pm'     => ['/data/web2.perl'],
    },
}
