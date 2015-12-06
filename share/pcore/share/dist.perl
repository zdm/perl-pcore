{   dist => {
        name             => '<: $dist_name :>',
        author           => '<: $author :> <<: $author_email :>>',
        license          => '<: $license :>',
        copyright_holder => '<: $copyright_holder :>',
        cpan             => <: $cpan_distribution :>,                # CPAN distribution
        cpan_bin         => 0,                                       # upload bin to CPAN
        meta             => {
            homepage   => q[],
            repository => {
                web  => q[],
                url  => q[],
                type => q[],
            },
            bugtracker => {                                          #
                web => q[],
            }
        },
        par => {
            'bin/<: $main_script :>' => {
                crypt     => 1,
                upx       => 1,
                clean     => 1,
                resources => [

                    # '<path_to_local_resource_file_or_dir>',
                ],
            },
        },
    },
}
