package Pcore::Util::PM::RPC::Proc;

use Pcore -class;
use Fcntl;
use Config;
use Pcore::AE::Handle;
use AnyEvent::Util qw[portable_socketpair];
use Pcore::Util::Scalar qw[weaken];
use if $MSWIN, 'Win32API::File';

has proc => ( is => 'ro', isa =>, InstanceOf ['Pcore::Util::PM::Proc'], init_arg => undef );
has pid => ( is => 'ro', isa => Int, init_arg => undef );    # real RPC process PID, reported in handshake
has in  => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], init_arg => undef );    # process IN channel, we can write
has out => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], init_arg => undef );    # process OUT channel, we can read

around new => sub ( $orig, $self, @ ) {
    my %args = (
        class     => undef,
        buildargs => undef,                                                               # class constructor arguments
        scan_deps => 0,
        on_ready  => undef,
        splice @_, 2,
    );

    # create self instance
    $self = $self->$orig;

    # create handles
    my ( $in_r,  $in_w )  = portable_socketpair();
    my ( $out_r, $out_w ) = portable_socketpair();

    state $perl = do {
        if ( $ENV->is_par ) {
            "$ENV{PAR_TEMP}/perl" . ( $MSWIN ? '.exe' : q[] );
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
        class     => $args{class},
        buildargs => $args{buildargs},
        scan_deps => $args{scan_deps},
    };

    if ($MSWIN) {
        $boot_args->{ipc} = {
            in  => Win32API::File::FdGetOsFHandle( fileno $in_r ),
            out => Win32API::File::FdGetOsFHandle( fileno $out_w ),
        };
    }
    else {
        fcntl $in_r,  Fcntl::F_SETFD, fcntl( $in_r,  Fcntl::F_GETFD, 0 ) & ~Fcntl::FD_CLOEXEC or die;
        fcntl $out_w, Fcntl::F_SETFD, fcntl( $out_w, Fcntl::F_GETFD, 0 ) & ~Fcntl::FD_CLOEXEC or die;

        $boot_args->{ipc} = {
            in  => fileno $in_r,
            out => fileno $out_w,
        };
    }

    # serialize CBOR + HEX
    $boot_args = P->data->to_cbor( $boot_args, encode => 2 )->$*;

    my $cmd = [];

    if ($MSWIN) {
        push $cmd->@*, $perl, q[-MPcore::Util::PM::RPC::Server -e "" ] . $boot_args;
    }
    else {
        push $cmd->@*, $perl, '-MPcore::Util::PM::RPC::Server', '-e', q[], $boot_args;
    }

    # needed for PAR, pass current @INC libs to child process via $ENV{PERL5LIB}
    local $ENV{PERL5LIB} = join $Config{path_sep}, grep { !ref } @INC;

    $self->{in}  = $in_w;
    $self->{out} = $out_r;

    # create proc
    P->pm->run_proc(
        $cmd,
        on_ready => sub ($proc) {
            $self->{proc} = $proc;

            # wrap AE handles and perform handshale
            $self->_handshake(
                sub {
                    $args{on_ready}->($self);

                    return;
                }
            );

            return;
        },
    );

    return;
};

sub _handshake ( $self, $cb ) {
    weaken $self;

    # wrap IN
    Pcore::AE::Handle->new(
        fh         => $self->{in},
        on_connect => sub ( $h, @ ) {
            $self->{in} = $h;

            return;
        },
    );

    # wrap OUT
    Pcore::AE::Handle->new(
        fh         => $self->{out},
        on_connect => sub ( $h, @ ) {
            $self->{out} = $h;

            return;
        },
    );

    # handshake
    $self->{out}->push_read(
        line => "\x00",
        sub ( $h, $line, $eol ) {
            if ( $line =~ /\AREADY(\d+)\z/sm ) {
                $self->{pid} = $1;

                $cb->();
            }
            else {
                die 'RPC handshake error';
            }

            return;
        }
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 132                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC::Proc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
