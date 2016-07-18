package Pcore::Util::PM::RPC::Proc;

use Pcore -class;
use Fcntl;
use Config;
use Pcore::AE::Handle;
use AnyEvent::Util qw[portable_socketpair];
use Pcore::Util::Scalar qw[weaken];
use if $MSWIN, 'Win32API::File';
use Pcore::Util::Data qw[:CONST];

has proc => ( is => 'ro', isa =>, InstanceOf ['Pcore::Util::PM::Proc'], init_arg => undef );
has pid => ( is => 'ro', isa => Int, init_arg => undef );    # real RPC process PID, reported in handshake
has in  => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], init_arg => undef );    # process IN channel, we can write
has out => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], init_arg => undef );    # process OUT channel, we can read
has on_finish => ( is => 'rw', isa => Maybe [CodeRef] );

around new => sub ( $orig, $self, @ ) {
    my %args = (
        class     => undef,
        buildargs => undef,                                                               # class constructor arguments
        on_ready  => undef,
        on_finish => undef,
        splice @_, 2,
    );

    # create self instance
    $self = $self->$orig( { on_finish => $args{on_finish} } );

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

    my $boot_args = [ $ENV->{SCRIPT_PATH}, $main::VERSION->normal, $ENV->{SCAN_DEPS} ];

    if ($MSWIN) {
        push $boot_args->@*, Win32API::File::FdGetOsFHandle( fileno $in_r ), Win32API::File::FdGetOsFHandle( fileno $out_w );
    }
    else {
        fcntl $in_r,  Fcntl::F_SETFD, fcntl( $in_r,  Fcntl::F_GETFD, 0 ) & ~Fcntl::FD_CLOEXEC or die;
        fcntl $out_w, Fcntl::F_SETFD, fcntl( $out_w, Fcntl::F_GETFD, 0 ) & ~Fcntl::FD_CLOEXEC or die;

        push $boot_args->@*, fileno $in_r, fileno $out_w;
    }

    # serialize CBOR + HEX
    $boot_args = P->data->to_cbor( $boot_args, encode => $DATA_ENC_HEX )->$*;

    my $cmd = [];

    if ($MSWIN) {
        push $cmd->@*, $perl, qq[-MPcore::Util::PM::RPC::Server -e "" $args{class}];
    }
    else {
        push $cmd->@*, $perl, '-MPcore::Util::PM::RPC::Server', '-e', q[], $args{class};
    }

    # needed for PAR, pass current @INC libs to child process via $ENV{PERL5LIB}
    local $ENV{PERL5LIB} = join $Config{path_sep}, grep { !ref } @INC;

    $self->{in}  = $in_w;
    $self->{out} = $out_r;

    # create proc
    P->pm->run_proc(
        $cmd,
        stdin    => 1,
        on_ready => sub ($proc) {
            $self->{proc} = $proc;

            $proc->stdin->push_write( $boot_args . $LF );

            # wrap AE handles and perform handshale
            $self->_handshake(
                {   class     => $args{class},
                    buildargs => $args{buildargs},
                },
                sub {
                    $args{on_ready}->($self);

                    return;
                }
            );

            return;
        },
        on_finish => sub ($proc) {
            $self->on_finish->($self) if $self->on_finish;

            return;
        }
    );

    return;
};

sub _handshake ( $self, $init, $cb ) {
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
            if ( $line =~ /\AREADY1(\d+)\z/sm ) {
                $self->{pid} = $1;

                my $cbor = P->data->to_cbor($init);

                $self->{in}->push_write( pack( 'L>', bytes::length $cbor->$* ) . $cbor->$* );

                $self->{out}->push_read(
                    line => "\x00",
                    sub ( $h, $line, $eol ) {
                        if ( $line =~ /\AREADY2(\d+)\z/sm ) {
                            $cb->();
                        }
                        else {
                            die 'RPC handshake error';
                        }
                    }
                );
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
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 131, 141             | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
