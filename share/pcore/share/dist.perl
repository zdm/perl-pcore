{   dist => {
        name             => '<: $dist_name :>',
        author           => '<: $author :> <<: $author_email :>>',
        license          => '<: $license :>',
        copyright_holder => '<: $copyright_holder :>',
        cpan             => <: $cpan_distribution :>,                # CPAN distribution
        cpan_bin         => 0,                                       # upload bin/*.* to CPAN
        meta             => {
            homepage   => undef,
            repository => {
                web  => undef,
                url  => undef,
                type => undef,
            },
            bugtracker => {                                          #
                web => undef,
            }
        },
    },

    util => {},

    par_mod_share => {},

    par => {
        '<: $main_script :>' => {
            crypt => 1,
            upx   => 1,
            clean => 1,
            share => [    # eg.: '/data/web2.perl',
            ],
        },
    },

}
