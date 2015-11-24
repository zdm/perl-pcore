{   dist => {
        name             => '<: $dist_name :>',
        author           => '<: $author :> <<: $author_email :>>',
        license          => '<: $license :>',
        copyright_holder => '<: $copyright_holder :>',
        cpan             => <: $cpan_distribution :>,              # 1 - CPAN distribution
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
                noupx     => 0,
                clean     => 1,
                resources => [

                    # [ local => '<path_to_local_resource_file_or_dir>' ],
                    # [ share => '<path_to_share_resource_file_or_dir>' ],
                ],
            },
        },
    },
}
