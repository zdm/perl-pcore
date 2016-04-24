{
    # shared resources, used by modules in this distribution
    mod_share => {

        # eg.:
        # 'Distribution/Module/Name.pm' => ['/data/pcore.perl', '/data/web2.perl'],
    },

    # scripts
    script => {
        '<: $main_script :>' => {
            crypt => 1,    # crypt PAR by default
            upx   => 1,    # compress DLLs with upx by default
            clean => 1,    # clean PAR cache on exit
        },
    },
}
