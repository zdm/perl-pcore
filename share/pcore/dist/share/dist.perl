{   dist => {
        name             => '<: $dist_name :>',
        author           => '<: $author :> <<: $author_email :>>',
        license          => '<: $license :>',                        # https://metacpan.org/pod/Software::License#SEE-ALSO
        copyright_holder => '<: $copyright_holder :>',
        cpan             => <: $cpan_distribution :>,                # CPAN distribution
        cpan_bin         => 0,                                       # upload bin/*.* to CPAN
        meta             => {
            homepage   => undef,                                     # project homepage url
            repository => {
                web  => undef,                                       # repository web url
                url  => undef,                                       # repository clone url
                type => undef,                                       # hg, git
            },
            bugtracker => {
                web => undef,                                        # bugtracker url
            }
        },
    },

    # Pcore utils, provided by this distribution
    util => {

        # eg.:
        # util_accessor_name => 'Util::Package::Name'
        # and lateer in the code you can use: P->util_accessor_name->
    },

    # shared resources, used by modules in this distribution
    mod_share => {

        # eg.:
        # 'Distribution/Module/Name.pm' => ['/data/pcore.perl', '/data/web2.perl'],
    },
}
