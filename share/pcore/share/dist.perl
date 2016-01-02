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
        par => {
            '<: $main_script :>' => {
                crypt     => 1,
                upx       => 1,
                clean     => 1,
                resources => [                                       #
                    '/data/web2.perl',                               # !!!WARN!!! required by Pcore::Util::URI
                ],
            },
        },
    },
}
