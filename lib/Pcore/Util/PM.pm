package Pcore::Util::PM;

use Pcore;
use POSIX qw[];

sub rename_process {
    return 0 if *threads::tid{CODE} && threads->tid != 0;    # don't allow rename process from thread

    $0 = shift;                                              ## no critic (Variables::RequireLocalizedPunctuationVars)

    return 1;
}

sub change_priv {
    my %args = (
        gid => undef,
        uid => undef,
        @_,
    );

    if ( !$MSWIN ) {
        if ( defined $args{gid} ) {
            my $gid = $args{gid} =~ /\A\d+\z/sm ? $args{gid} : getgrnam $args{gid};

            croak qq[Can't find gid: "$args{gid}"] if !defined $gid;

            POSIX::setgid($gid) or die qq[Can't set GID to "$args{gid}". $!];
        }

        if ( defined $args{uid} ) {
            my $uid = $args{uid} =~ /\A\d+\z/sm ? $args{uid} : getpwnam $args{uid};

            croak qq[Can't find uid "$args{uid}"] if !defined $uid;

            POSIX::setuid($uid) or die qq[Can't set UID to "$args{uid}". $!];
        }
    }

    return;
}

sub daemonize {
    state $daemonized = 0;

    return 0 if $daemonized;

    $daemonized++;

    P->EV->throw('CORE#DAEMONIZE');

    if ( !$MSWIN ) {
        fork && exit 0;    ## no critic qw[InputOutput::RequireCheckedSyscalls]

        open STDIN, '+<', '/dev/null' or die;
        open STDOUT, '>&STDIN' or die;
        open STDERR, '>&STDIN' or die;

        open $STDOUT_UTF8, '>&STDIN' or die;    ## no critic qw[InputOutput::RequireBriefOpen]
        open $STDERR_UTF8, '>&STDIN' or die;    ## no critic qw[InputOutput::RequireBriefOpen]

        POSIX::setsid() or die qq[Can't set sid: $!];

        return 1;
    }

    return 0;
}

sub is_process_alive {
    my $process_name = shift;

    if ($MSWIN) {
        return;
    }
    else {
        require Proc::ProcessTable;

        my $t = Proc::ProcessTable->new;

        for ( $t->table->@* ) {
            my $cmndline = $_->cmndline;

            if ( ref $process_name eq 'Regexp' ) {
                return $_->pid if ( defined $cmndline && $cmndline =~ /$process_name/sm && $_->pid != $$ );
            }
            else {
                return $_->pid if ( defined $cmndline && $cmndline eq $process_name && $_->pid != $$ );
            }
        }
        return 0;
    }
}

sub is_superuser {
    if ($MSWIN) {
        return Win32::IsAdminUser();
    }
    else {
        return $> == 0 ? 1 : 0;
    }
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM - pcore processs management util functions

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
