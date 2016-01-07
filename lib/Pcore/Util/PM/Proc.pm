package Pcore::Util::PM::Proc;

use Pcore -class;
use Pcore::AE::Handle;
use AnyEvent::Util qw[portable_socketpair];
use if $MSWIN, 'Win32::Process';

has cmd => ( is => 'ro', isa => ArrayRef, required => 1 );

# TODO
# stderr - 0, 1, 2 - merge with stdout
has stdin  => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );    # process STDIN, we can write
has stdout => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );    # process STDOUT, we can read
has stderr => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );    # process STDERR, we can read

has std        => ( is => 'ro', isa => Bool, default => 0 );              # capture process STD* handles
has std_merged => ( is => 'ro', isa => Bool, default => 0 );              # merge STDOUT and STDERR into STDOUT

has console => ( is => 'ro', isa => Bool, default => 1 );
has blocking => ( is => 'ro', isa => Bool | InstanceOf ['AnyEvent::CondVar'], default => 1 );
has on_ready => ( is => 'ro', isa => Maybe [CodeRef] );                   # ($self), called, when process created, pid captured and handles are ready
has on_error => ( is => 'ro', isa => Maybe [CodeRef] );                   # ($self, $status), called, when exited with !0 status
has on_exit  => ( is => 'ro', isa => Maybe [CodeRef] );                   # ($self, $status), called on process exit

has mswin_alive_timout => ( is => 'ro', isa => Num, default => 0.5 );

has pid => ( is => 'ro', isa => PositiveInt, init_arg => undef );
has status => ( is => 'ro', isa => Maybe [PositiveOrZeroInt], init_arg => undef );    # undef - process still alive

has _cv      => ( is => 'ro', isa => InstanceOf ['AnyEvent::CondVar'], init_arg => undef );
has _winproc => ( is => 'ro', isa => InstanceOf ['Win32::Process'],    init_arg => undef );    # windows process descriptor

around new => sub ( $orig, $self, $args ) {
    $args->{_wantarray} = defined wantarray ? 1 : 0;

    return $self->$orig($args);
};

sub BUILD ( $self, $args ) {
    $args->{_wantarray} //= 1;

    P->scalar->weaken($self) if $args->{_wantarray};

    my $blocking;

    if ( $self->blocking ) {
        if ( ref $self->blocking ) {
            $self->{_cv} = $self->blocking;
        }
        else {
            $self->{_cv} = AE::cv;

            $blocking = 1;
        }

        $self->{_cv}->begin;
    }

    my $on_ready = AE::cv {
        $self->on_ready->($self) if $self->on_ready;

        my $on_exit = sub ($status) {
            undef $self->{sigchild};

            $self->{_cv}->end if $self->{_cv};

            $self->{status} = $status;

            $self->on_error->( $self, $status ) if $status and $self->on_error;

            $self->on_exit->( $self, $status ) if $self->on_exit;

            return;
        };

        if ($MSWIN) {
            $self->{sigchild} = AE::timer 0, $self->mswin_alive_timout, sub {
                $self->{_winproc}->GetExitCode( my $status );

                $on_exit->($status) if $status != Win32::Process::STILL_ACTIVE();

                return;
            };
        }
        else {
            $self->{sigchild} = AE::child $self->pid, sub ( $pid, $status ) {
                $on_exit->( $status >> 8 );

                return;
            };
        }

        return;
    };

    $self->_create( $on_ready, $self->cmd );

    $self->{_cv}->recv if $blocking;

    return;
}

sub DEMOLISH ( $self, $global ) {
    if ( $self->pid ) {

        # kill process group, eg.: windows console subprocess
        kill -9, $self->pid;    ## no critic qw[InputOutput::RequireCheckedSyscalls]

        # kill process, because -9 is ignoref by process itself
        kill 9, $self->pid;     ## no critic qw[InputOutput::RequireCheckedSyscalls]
    }

    $self->{_cv}->end if $self->{_cv};

    return;
}

sub _create ( $self, $on_ready, $args ) {
    my $cmd;

    if ($MSWIN) {
        $cmd = [ $ENV{COMSPEC}, join q[ ], '/D /C', $args->@* ];
    }
    else {
        $cmd = $args;
    }

    my $h;

    if ( $self->std ) {
        ( $h->{in_r},  $h->{in_w} )  = portable_socketpair();
        ( $h->{out_r}, $h->{out_w} ) = portable_socketpair();
        ( $h->{err_r}, $h->{err_w} ) = portable_socketpair() if !$self->std_merged;

        # save STD* handles
        open $h->{old_in},  '<&', *STDIN  or die;
        open $h->{old_out}, '>&', *STDOUT or die;
        open $h->{old_err}, '>&', *STDERR or die;

        # redirect STD* handles
        open STDIN,  '<&', $h->{in_r}  or die;
        open STDOUT, '>&', $h->{out_w} or die;
        if ( $self->std_merged ) {
            open STDERR, '>&', $h->{out_w} or die;
        }
        else {
            open STDERR, '>&', $h->{err_w} or die;
        }
    }

    if ($MSWIN) {
        Win32::Process::Create(    #
            my $proc,
            $cmd->@*,
            1,                     # inherit STD* handles
            ( $self->console ? 0 : Win32::Process::CREATE_NO_WINDOW() ),    # WARNING: not works if not 0, Win32::Process::CREATE_NO_WINDOW(),
            q[.]
        );

        die q[Can't create process] if !$proc;

        $self->{_winproc} = $proc;

        $self->{pid} = $proc->GetProcessID;
    }
    else {
        unless ( $self->{pid} = fork ) {
            exec $cmd->@* or die $!;
        }
    }

    $on_ready->begin;

    if ( $self->std ) {

        # restore STD* handles
        open STDIN,  '<&', $h->{old_in}  or die;
        open STDOUT, '>&', $h->{old_out} or die;
        open STDERR, '>&', $h->{old_err} or die;

        P->scalar->weaken($self);

        $on_ready->begin;
        Pcore::AE::Handle->new(
            fh         => $h->{in_w},
            on_connect => sub ( $h, @ ) {
                $self->{stdin} = $h;

                $on_ready->end;

                return;
            },
        );

        $on_ready->begin;
        Pcore::AE::Handle->new(
            fh         => $h->{out_r},
            on_connect => sub ( $h, @ ) {
                $self->{stdout} = $h;

                $on_ready->end;

                return;
            },
        );

        if ( !$self->std_merged ) {
            $on_ready->begin;
            Pcore::AE::Handle->new(
                fh         => $h->{err_r},
                on_connect => sub ( $h, @ ) {
                    $self->{stderr} = $h;

                    $on_ready->end;

                    return;
                },
            );
        }
    }

    $on_ready->end;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 118                  │ Subroutines::ProhibitExcessComplexity - Subroutine "_create" with high complexity score (25)                   │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::Proc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
