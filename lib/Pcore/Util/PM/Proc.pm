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

    $self->_create_proc( $cv, $self->cmd );

    return;
}

sub _create_proc ( $self, $on_ready, $args ) {
    my $cmd;

    if ($MSWIN) {
        $cmd = [ $ENV{COMSPEC}, join q[ ], '/D /C', $args->@* ];
    }
    else {
        $cmd = $args;
    }

    my $h;

    if ( $self->capture_std ) {
        ( $h->{in},     $h->{out_svr} ) = portable_socketpair();
        ( $h->{in_svr}, $h->{out} )     = portable_socketpair();
        ( $h->{err},    $h->{err_svr} ) = portable_socketpair();

        # save STD* handles
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

    $on_ready->begin;

    if ( $self->capture_std ) {

        # restore STD* handles
        open STDIN,  '<&', $h->{old_in}  or die;
        open STDOUT, '>&', $h->{old_out} or die;
        open STDERR, '>&', $h->{old_err} or die;

        P->scalar->weaken($self);

        my $cv = AE::cv {
            $on_ready->end;

            return;
        };

        $cv->begin;

        Pcore::AE::Handle->new(
            fh         => $h->{in},
            on_connect => sub ( $h, @ ) {
                $self->{stdin} = $h;

                $cv->end;

                return;
            },
        );

        $cv->begin;

        Pcore::AE::Handle->new(
            fh         => $h->{out},
            on_connect => sub ( $h, @ ) {
                $self->{stdout} = $h;

                $cv->end;

                return;
            },
        );

        $cv->begin;

        Pcore::AE::Handle->new(
            fh         => $h->{err},
            on_connect => sub ( $h, @ ) {
                $self->{stderr} = $h;

                $cv->end;

                return;
            },
        );
    }
    else {
        $on_ready->end;
    }

    return;
}

1;
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
