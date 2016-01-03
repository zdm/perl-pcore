package Pcore::Util::PM;

use Pcore -export, [qw[is_superuser proc]];
use POSIX qw[];
use Config;

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

sub proc {
    state $init = !!require Pcore::Util::PM::Process;

    return Pcore::Util::PM::Process->new(@_);
}

sub create_process (@args) {
    state $init = do {
        if ($MSWIN) {
            require Win32API::File;
            require Win32::Process;
        }

        1;
    };

    my $pid;

    my $wrap_perl;

    if ( ref $args[0] eq 'SCALAR' ) {
        $wrap_perl = 1;

        $args[0] = $args[0]->$*;

        P->text->cut_all( $args[0] );

        $args[0] =~ s/\n//smg;

        state $perl = do {
            if ( $ENV->is_par ) {
                "$ENV{PAR_TEMP}/perl" . $MSWIN ? '.exe' : q[];
            }
            else {
                $^X;
            }
        };

        if ($MSWIN) {
            @args = ( $ENV{COMSPEC}, qq[/D /C $perl -e "$args[0]"] );
        }
        else {
            @args = ( $perl, '-e', $args[0] );
        }
    }

    local $ENV{PERL5LIB} = join $Config{path_sep}, grep { !ref } @INC if $wrap_perl;

    if ($MSWIN) {
        Win32::Process::Create(    #
            my $process,
            @args,
            1,                     # inherit STD* handles
            0,                     # WARNING: not works if not 0, Win32::Process::CREATE_NO_WINDOW(),
            q[.]
        ) || die $!;

        $pid = $process->GetProcessID;
    }
    else {
        unless ( $pid = fork ) {
            exec @args or die;
        }
    }

    return $pid;
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
