package Pcore::Util::Sys;

use Pcore;

sub cpus_num {
    state $cpus_num = do {
        require Sys::CpuAffinity;

        Sys::CpuAffinity::getNumCpus();
    };

    return $cpus_num;
}

sub hostname {
    state $hostname = do {
        require Sys::Hostname;    ## no critic qw[Modules::ProhibitEvilModules]

        Sys::Hostname::hostname();
    };

    return $hostname;
}

1;
__END__
=pod

=encoding utf8

=cut
