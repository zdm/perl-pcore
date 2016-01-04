package Pcore::Util::PM;

use Pcore -export, [qw[is_superuser run_rpc run_ipc]];
use POSIX qw[];

sub rename_process {
    $0 = shift;    ## no critic (Variables::RequireLocalizedPunctuationVars)

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

sub is_superuser {
    if ($MSWIN) {
        return Win32::IsAdminUser();
    }
    else {
        return $> == 0 ? 1 : 0;
    }
}

sub run_rpc ( $class, @ ) {
    my %args = (
        args        => {},
        on_ready    => undef,
        on_exit     => undef,
        workers     => 0,
        capture_std => 0,
        splice( @_, 1 ),
        class => $class,
    );

    state $init = !!require Pcore::Util::PM::RPC;

    return Pcore::Util::PM::RPC->new( \%args );
}

sub run_ipc (@) {
    my %args = (
        cmd         => undef,
        capture_std => 1,
        on_ready    => undef,
        on_exit     => undef,
        @_,
    );

    state $init = !!require Pcore::Util::PM::Proc;

    return Pcore::Util::PM::Proc->new( \%args );
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
