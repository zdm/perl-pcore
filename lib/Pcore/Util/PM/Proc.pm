package Pcore::Util::PM::Proc;

use Pcore -class;
use Pcore::AE::Handle;
use AnyEvent::Util qw[portable_socketpair];
use if $MSWIN, 'Win32::Process';

has cmd         => ( is => 'ro', isa => ArrayRef, required => 1 );
has capture_std => ( is => 'ro', isa => Bool,     default  => 0 );
has on_ready => ( is => 'ro', isa => Maybe [CodeRef] );
has on_exit  => ( is => 'ro', isa => Maybe [CodeRef] );

has pid => ( is => 'ro', isa => PositiveInt, init_arg => undef );
has exit_code => ( is => 'ro', isa => PositiveOrZeroInt, default => 0, init_arg => undef );

has stdin  => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );
has stdout => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );
has stderr => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );

sub DEMOLISH ( $self, $global ) {
    if ($MSWIN) {
        Win32::Process::KillProcess( $self->pid, 0 ) if $self->pid;
    }
    else {
        kill 9, $self->pid or 1 if $self->pid;
    }

    return;
}

sub BUILD ( $self, $args ) {
    $self->_create;

    return;
}

sub _create ($self) {
    my $cv = AE::cv {
        $self->on_ready->($self) if $self->on_ready;

        return;
    };

    $self->_create_process( $cv, $self->cmd );

    return;
}

sub _create_proc ( $self, $cv, $args ) {
    my $cmd;

    if ($MSWIN) {
        $cmd = [ $ENV{COMSPEC}, join q[ ], '/D /C', $args->@* ];
    }
    else {
        $cmd = $args->@*;
    }

    my $h;

    if ( $self->capture_std ) {
        ( $h->{in},     $h->{out_svr} ) = portable_socketpair();
        ( $h->{in_svr}, $h->{out} )     = portable_socketpair();
        ( $h->{err},    $h->{err_svr} ) = portable_socketpair();

        # store old STD* handles
        open $h->{old_in},  '<&', *STDIN  or die;
        open $h->{old_out}, '>&', *STDOUT or die;
        open $h->{old_err}, '>&', *STDERR or die;

        # redirect STD* handles
        open STDIN,  '<&', $h->{in_svr}  or die;
        open STDOUT, '>&', $h->{out_svr} or die;
        open STDERR, '>&', $h->{err_svr} or die;
    }

    if ($MSWIN) {
        Win32::Process::Create(    #
            my $process,
            $cmd->@*,
            1,                     # inherit STD* handles
            0,                     # WARNING: not works if not 0, Win32::Process::CREATE_NO_WINDOW(),
            q[.]
        ) || die $!;

        $self->{pid} = $process->GetProcessID;
    }
    else {
        unless ( $self->{pid} = fork ) {
            exec $cmd->@* or die $!;
        }
    }

    $cv->begin;

    if ( $self->capture_std ) {

        # restore STD* handles
        open STDIN,  '<&', $h->{old_in}  or die;
        open STDOUT, '>&', $h->{old_out} or die;
        open STDERR, '>&', $h->{old_err} or die;

        P->scalar->weaken($self);

        my $cv1 = AE::cv {
            $cv->end;

            return;
        };

        $cv1->begin;

        Pcore::AE::Handle->new(
            fh         => $h->{in},
            on_connect => sub ( $h, @ ) {
                $self->{stdin} = $h;

                $cv1->end;

                return;
            },
        );

        $cv1->begin;

        Pcore::AE::Handle->new(
            fh         => $h->{out},
            on_connect => sub ( $h, @ ) {
                $self->{stdout} = $h;

                $cv1->end;

                return;
            },
        );

        $cv1->begin;

        Pcore::AE::Handle->new(
            fh         => $h->{err},
            on_connect => sub ( $h, @ ) {
                $self->{stderr} = $h;

                $cv1->end;

                return;
            },
        );
    }
    else {
        $cv->end;
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 49                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_create_proc' declared but not used │
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
