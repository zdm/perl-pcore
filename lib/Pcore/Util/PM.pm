package Pcore::Util::PM;

use Pcore -export, [qw[is_superuser run run_capture run_check run_rpc]];
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

sub run (@) {
    my %args = (
        cmd      => undef,
        std      => 0,
        console  => 1,
        blocking => 1,
        on_ready => undef,
        on_error => undef,
        on_exit  => undef,
        @_,
    );

    state $init = !!require Pcore::Util::PM::Proc;

    return Pcore::Util::PM::Proc->new( \%args );
}

sub run_capture (@cmd) {
    my ( $stdout, $stderr );

    my $wantarray = wantarray;

    my %args = (
        cmd        => \@cmd,
        std        => 1,
        std_merged => $wantarray ? 0 : 1,
        console    => 1,
        blocking   => 1,
        on_ready   => sub ($self) {
            $self->stdout->on_read( sub { } );
            $self->stdout->on_eof(undef);
            $self->stdout->on_error(
                sub {
                    $stdout = delete $_[0]{rbuf};

                    return;
                }
            );

            if ($wantarray) {
                $self->stderr->on_read( sub { } );
                $self->stderr->on_eof(undef);
                $self->stderr->on_error(
                    sub {
                        $stderr = delete $_[0]{rbuf};

                        return;
                    }
                );
            }

            return;
        },
        on_error => undef,
        on_exit  => undef,
    );

    state $init = !!require Pcore::Util::PM::Proc;

    my $p = Pcore::Util::PM::Proc->new( \%args );

    return $wantarray ? ( $stdout, $stderr, $p->status ) : $stdout;
}

sub run_check (@cmd) {
    my %args = (
        cmd      => \@cmd,
        std      => 0,
        console  => 1,
        blocking => 1,
        on_ready => undef,
        on_error => undef,
        on_exit  => undef,
    );

    state $init = !!require Pcore::Util::PM::Proc;

    my $p = Pcore::Util::PM::Proc->new( \%args );

    if ( defined wantarray ) {
        return $p->status ? undef : 1;
    }
    elsif ( $p->status ) {
        die 'Error exec process, process exit code: ' . $p->status;
    }
    else {
        return 1;
    }
}

sub run_rpc ( $class, @ ) {
    my %args = (
        args     => {},
        workers  => 0,
        std      => 0,
        console  => 1,
        on_ready => undef,
        splice( @_, 1 ),
        class => $class,
    );

    state $init = !!require Pcore::Util::PM::RPC;

    return Pcore::Util::PM::RPC->new( \%args );
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
