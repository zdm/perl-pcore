package Pcore::Util::PM::RPC::Proc;

use Pcore -class;
use Fcntl;
use Config;
use AnyEvent::Util qw[portable_socketpair];
use if $MSWIN, 'Win32API::File';

extends qw[Pcore::Util::PM::Proc];

has '+cmd' => ( required => 0, init_arg => undef );

has class     => ( is => 'ro', isa => Str,     required => 1 );
has args      => ( is => 'ro', isa => HashRef, required => 1 );
has scan_deps => ( is => 'ro', isa => Bool,    required => 1 );
has on_data => ( is => 'ro', isa => Maybe [CodeRef], required => 1 );

has in  => ( is => 'lazy', isa => InstanceOf ['Pcore::AE::Handle'] );
has out => ( is => 'lazy', isa => InstanceOf ['Pcore::AE::Handle'] );

around _create => sub ( $orig, $self ) {
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
        class     => $self->class,
        args      => $self->args,
        scan_deps => $self->scan_deps,
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

    my $cmd = [];

    if ($MSWIN) {
        push $cmd->@*, $perl, q[-MPcore::Util::PM::RPC::Server -e "" ] . $boot_args;
    }
    else {
        push $cmd->@*, $perl, '-MPcore::Util::PM::RPC::Server', '-e', q[], $boot_args;
    }

    local $ENV{PERL5LIB} = join $Config{path_sep}, grep { !ref } @INC;

    my $cv = AE::cv {

        # start listener
        $self->in->on_read(
            sub ($h) {
                $h->unshift_read(
                    chunk => 4,
                    sub ( $h, $data ) {
                        my $len = unpack 'L>', $data;

                        $h->unshift_read(
                            chunk => $len,
                            sub ( $h, $data ) {
                                $self->on_data->( P->data->from_cbor($data) ) if $self->on_data;

                                return;
                            }
                        );

                        return;
                    }
                );

                return;
            }
        );

        $self->on_ready->($self) if $self->on_ready;

        return;
    };

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

    $self->_create_proc( $cv, $cmd );

    return;
};

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 115                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
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
