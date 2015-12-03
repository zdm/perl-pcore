package Pcore::Util::Sys;

use Pcore;

# in case of error return undef
sub system {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my $self = shift;

    CORE::system(@_);

    die qq[System call exit code: $?] if $? && !defined wantarray;

    return if $?;

    return 1;
}

sub cpus_num {
    require Sys::CpuAffinity;

    state $cpus_num = Sys::CpuAffinity::getNumCpus();

    return $cpus_num;
}

# return PID combined with TID (if threads used)
sub pid {
    my $self = shift;

    return *threads::tid{CODE} ? qq[$$-] . threads->tid : qq[$$-0];
}

sub hostname {
    my $self = shift;

    require Sys::Hostname;    ## no critic qw[Modules::ProhibitEvilModules]

    state $hostname = Sys::Hostname::hostname();

    return $hostname;
}

1;
__END__
=pod

=encoding utf8

=cut
