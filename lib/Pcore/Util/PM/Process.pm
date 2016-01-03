package Pcore::Util::PM::Process;

use Pcore -class;
use Config qw[%Config];
use Fcntl;
use AnyEvent::Util qw[portable_socketpair];
use Pcore::AE::Handle;
use if $MSWIN, 'Win32::Process';
use if $MSWIN, 'Win32API::File';

has rpc => ( is => 'ro', isa => Bool, required => 1 );
has rpc_class   => ( is => 'ro', isa => Str );
has args        => ( is => 'ro', isa => ArrayRef | HashRef );
has capture_std => ( is => 'ro', isa => Bool, default => 0 );
has on_ready => ( is => 'ro', isa => Maybe [CodeRef] );
has on_exit  => ( is => 'ro', isa => Maybe [CodeRef] );

has in  => ( is => 'lazy', isa => InstanceOf ['Pcore::AE::Handle'] );
has out => ( is => 'lazy', isa => InstanceOf ['Pcore::AE::Handle'] );

has stdin  => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );
has stdout => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );
has stderr => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'] );

has exit_code => ( is => 'ro', isa => PositiveOrZeroInt, default => 0, init_arg => undef );
has pid => ( is => 'ro', isa => PositiveInt, init_arg => undef );

sub BUILD ( $self, $args ) {
    if ( $self->rpc ) {
        $self->_run_rpc;
    }
    else {
        $self->_run_ipc;
    }

    return;
}

sub DEMOLISH ( $self, $global ) {
    if ($MSWIN) {
        Win32::Process::KillProcess( $self->pid, 0 ) if $self->pid;
    }
    else {
        kill 9, $self->pid or 1 if $self->pid;
    }

    return;
}

sub _run_rpc ($self) {
    state $perl = do {
        if ( $ENV->is_par ) {
            "$ENV{PAR_TEMP}/perl" . $MSWIN ? '.exe' : q[];
        }
        else {
            $^X;
        }
    };

    my $boot_args = {
        script => {
            path    => $ENV->{SCRIPT_PATH},
            version => $main::VERSION->normal,
        },
        class => $self->rpc_class,
        args  => $self->args // {},
    };

    my ( $in,     $out_svr ) = portable_socketpair();
    my ( $in_svr, $out )     = portable_socketpair();

    if ($MSWIN) {
        $boot_args->{ipc} = {
            in  => Win32API::File::FdGetOsFHandle( fileno $in_svr ),
            out => Win32API::File::FdGetOsFHandle( fileno $out_svr ),
        };
    }
    else {
        fcntl $in_svr,  Fcntl::F_SETFD, fcntl( $in_svr,  Fcntl::F_GETFD, 0 ) & ~Fcntl::FD_CLOEXEC or die;
        fcntl $out_svr, Fcntl::F_SETFD, fcntl( $out_svr, Fcntl::F_GETFD, 0 ) & ~Fcntl::FD_CLOEXEC or die;

        $boot_args->{ipc} = {
            in  => fileno $in_svr,
            out => fileno $out_svr,
        };
    }

    # serialize CBOR + HEX
    $boot_args = P->data->to_cbor( $boot_args, encode => 2 )->$*;

    my @args;

    if ($MSWIN) {
        @args = ( $perl, q[-MPcore::Util::PM::Process::RPC::Server -e "" ] . $boot_args );
    }
    else {
        @args = ( $perl, '-MPcore::Util::PM::Process::RPC::Server', '-e', q[], $boot_args );
    }

    local $ENV{PERL5LIB} = join $Config{path_sep}, grep { !ref } @INC;

    my $cv = AE::cv {
        $self->on_ready->($self) if $self->on_ready;

        return;
    };

    # create process
    $self->_create_process( $cv, @args );

    # handshake
    $cv->begin;

    Pcore::AE::Handle->new(
        fh         => $in,
        on_connect => sub ( $h, @ ) {
            $self->{in} = $h;

            $self->{in}->push_read(
                line => "\x00",
                sub ( $h, $line, $eol ) {
                    if ( $line =~ /\AREADY(\d+)\z/sm ) {
                        $self->{pid} = $1;

                        $cv->end;
                    }
                    else {
                        die 'RPC handshake error';
                    }

                    return;
                }
            );

            return;
        },
    );

    $cv->begin;

    Pcore::AE::Handle->new(
        fh         => $out,
        on_connect => sub ( $h, @ ) {
            $self->{out} = $h;

            $cv->end;

            return;
        },
    );

    return;
}

sub _run_ipc ($self) {
    my $cv = AE::cv {
        $self->on_ready->($self) if $self->on_ready;

        return;
    };

    $self->_create_process( $cv, $self->args->@* );

    return;
}

sub _create_process ( $self, $cv, @args ) {
    @args = ( $ENV{COMSPEC}, '/D /C ' . join q[ ], @args ) if $MSWIN;

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
            @args,
            1,                     # inherit STD* handles
            0,                     # WARNING: not works if not 0, Win32::Process::CREATE_NO_WINDOW(),
            q[.]
        ) || die $!;

        $self->{pid} = $process->GetProcessID;
    }
    else {
        unless ( $self->{pid} = fork ) {
            exec @args or die $!;
        }
    }

    if ( $self->capture_std ) {

        # restore STD* handles
        open STDIN,  '<&', $h->{old_in}  or die;
        open STDOUT, '>&', $h->{old_out} or die;
        open STDERR, '>&', $h->{old_err} or die;

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

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 120                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::Process

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
