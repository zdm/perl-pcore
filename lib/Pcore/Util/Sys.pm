package Pcore::Util::Sys;

use Pcore;

# in case of error return undef
sub system {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    CORE::system @_;

    die qq[System call exit code: $?] if $? && !defined wantarray;

    return if $?;

    return 1;
}

sub cpus_num {
    state $cpus_num = do {
        require Sys::CpuAffinity;

        Sys::CpuAffinity::getNumCpus();
    };

    return $cpus_num;
}

# return PID combined with TID (if threads used)
sub pid {
    return *threads::tid{CODE} ? qq[$$-] . threads->tid : qq[$$-0];
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
