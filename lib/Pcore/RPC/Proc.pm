package Pcore::RPC::Proc;

use Pcore -class;
use Fcntl;
use Pcore::AE::Handle;
use AnyEvent::Util qw[portable_socketpair];
use if $MSWIN, 'Win32API::File';
use Pcore::Util::Data qw[:CONST];
use Pcore::Util::Scalar qw[weaken];

has proc => ( is => 'ro', isa =>, InstanceOf ['Pcore::Util::PM::Proc'], init_arg => undef );
has on_finish => ( is => 'rw', isa => Maybe [CodeRef] );

has conn => ( is => 'ro', isa => HashRef, init_arg => undef );

around new => sub ( $orig, $self, $type, % ) {
    my %args = (
        parent_id => undef,
        listen    => undef,    # RPC server listen
        token     => undef,
        buildargs => undef,    # class constructor arguments
        on_ready  => undef,
        on_finish => undef,
        @_[ 3 .. $#_ ],
    );

    # create self instance
    $self = $self->$orig( { on_finish => $args{on_finish} } );

    if ($Pcore::RPC::Tmpl::CPID) {
        Pcore::RPC::Tmpl::run(
            $type,
            {   parent_id => $args{parent_id},
                listen    => $args{listen},
                token     => $args{token},
                buildargs => $args{buildargs},
            },
            sub ($proc) {
                $args{on_ready}->($proc);

                return;
            }
        );

        return;
    }

    # create handles
    my ( $ctrl_r, $ctrl_w ) = portable_socketpair();

    state $perl = do {
        if ( $ENV->{is_par} ) {
            "$ENV{PAR_TEMP}/perl" . ( $MSWIN ? '.exe' : q[] );
        }
        else {
            $^X;
        }
    };

    my $boot_args = {
        script_path => $ENV->{SCRIPT_PATH},
        version     => $main::VERSION->normal,
        scandeps    => $ENV->{SCAN_DEPS} ? 1 : undef,
        parent_id   => $args{parent_id},
        listen      => $args{listen},
        token       => $args{token},
        buildargs   => $args{buildargs},
    };

    if ($MSWIN) {
        $boot_args->{ctrl_fh} = Win32API::File::FdGetOsFHandle( fileno $ctrl_w );
    }
    else {
        fcntl $ctrl_w, Fcntl::F_SETFD, fcntl( $ctrl_w, Fcntl::F_GETFD, 0 ) & ~Fcntl::FD_CLOEXEC or die;

        $boot_args->{ctrl_fh} = fileno $ctrl_w;
    }

    # serialize CBOR + HEX
    $boot_args = unpack 'H*', P->data->to_cbor($boot_args)->$*;

    my $cmd = [];

    if ($MSWIN) {
        push $cmd->@*, $perl, "-M$type";
    }
    else {
        push $cmd->@*, $perl, "-M$type";
    }

    my $weaken_self = $self;

    weaken $weaken_self;

    # create proc
    P->pm->run_proc(
        $cmd,
        stdin    => 1,
        on_ready => sub ($proc) {
            $self->{proc} = $proc;

            # send configuration to RPC STDIN
            $proc->stdin->push_write( $boot_args . $LF );

            # wrap AE handles and perform handshale
            $self->_handshake(
                $ctrl_r,
                sub {
                    $args{on_ready}->($self);

                    return;
                }
            );

            return;
        },
        on_finish => sub ($proc) {
            $weaken_self->{on_finish}->($weaken_self) if $weaken_self && $weaken_self->{on_finish};

            return;
        }
    );

    return;
};

sub _handshake ( $self, $ctrl_fh, $cb ) {

    # wrap control_fh
    Pcore::AE::Handle->new(
        fh         => $ctrl_fh,
        on_connect => sub ( $h, @ ) {
            $h->push_read(
                line => "\n",
                sub ( $h1, $line, $eol ) {

                    # destroy control fh
                    $h->destroy;

                    my $conn = eval { P->data->from_cbor($line) };

                    if ($@) {
                        die 'RPC handshake error';
                    }
                    else {
                        $self->{conn} = $conn;

                        $cb->();
                    }

                    return;
                }
            );

            return;
        },
    );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::RPC::Proc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
