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

# term width
sub term_width {
    state $required;

    if ( !defined $required ) {
        require Term::Size::Any;

        $required = Term::Size::Any::_require_any();
    }

    return scalar Term::Size::Any::chars();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 50                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
