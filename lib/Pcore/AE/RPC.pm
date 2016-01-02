package Pcore::AE::RPC;

use Pcore -class;
use AnyEvent::Util qw[portable_socketpair];
use Pcore::AE::RPC::Server;
use Config;

with qw[Pcore::AE::RPC::Base];

has on_ready => ( is => 'ro', isa => CodeRef );

has pid => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has call_id => ( is => 'ro', default => 0, init_arg => undef );
has queue => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );
has next_pid  => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has scan_deps => ( is => 'lazy', isa => Bool,     init_arg => undef );

sub BUILD ( $self, $args ) {
    my $cv = AE::cv;

    for ( 1 .. P->sys->cpus_num ) {
        $self->_run_server($cv);
    }

    $cv->recv;

    $self->on_ready->($self) if $self->on_ready;

    return;
}

sub DEMOLISH ( $self, $global ) {
    for my $pid ( keys $self->pid->%* ) {
        if ($MSWIN) {
            Win32::Process::KillProcess( $pid, 0 ) if $pid;
        }
        else {
            kill 9, $pid or 1 if $pid;
        }
    }

    return;
}

sub _build_next_pid ($self) {
    return [ keys $self->pid->%* ];
}

sub _build_scan_deps ($self) {
    return exists $INC{'Pcore/Devel/ScanDeps.pm'} ? 1 : 0;
}

sub _run_server ( $self, $ready ) {
    $ready->begin;

    my ( $in,       $out_child ) = portable_socketpair();
    my ( $in_child, $out )       = portable_socketpair();

    if ($MSWIN) {
        $self->_run_server_mswin( $in_child, $out_child );
    }
    else {
        $self->_run_server_linux( $in_child, $out_child );
    }

    my $pid;

    my $cv = AE::cv {
        $self->pid->{$pid} = [ $in, $out ];

        # run listener
        $self->start_listen(
            $in,
            sub ($data) {
                $self->_store_deps( $data->[0] ) if $data->[0] && $self->scan_deps;

                if ( my $cb = delete $self->queue->{ $data->[1] } ) {
                    $cb->( $data->[2] );
                }

                return;
            }
        );

        $ready->end;

        return;
    };

    # handshake
    $cv->begin;
    Pcore::AE::Handle->new(
        fh         => $in,
        on_connect => sub ( $h, @ ) {
            $in = $h;

            $in->push_read(
                line => "\x00",
                sub ( $h, $line, $eol ) {
                    if ( $line =~ /\AREADY(\d+)\z/sm ) {
                        $pid = $1;

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
            $out = $h;

            $cv->end;

            return;
        },
    );

    return;
}

sub _run_server_mswin ( $self, $in, $out ) {
    state $init = do {
        require Win32API::File;
        require Win32::Process;

        1;
    };

    my $code = $self->_get_code( Win32API::File::FdGetOsFHandle( fileno $in ), Win32API::File::FdGetOsFHandle( fileno $out ) );

    my $process;

    my $perl = $ENV->is_par ? 'perl.exe' : $^X;

    local $ENV{PERL5LIB} = join q[;], grep { !ref } @INC if $ENV->is_par;

    Win32::Process::Create(    #
        $process,
        $ENV{COMSPEC},
        qq[/D /C $perl -e "$code"],
        1,
        0,                     # WARNING: not works if not 0, Win32::Process::CREATE_NO_WINDOW(),
        q[.]
    ) || die $!;

    return;
}

# TODO run from PAR under Linux
sub _run_server_linux ( $self, $in, $out ) {
    state $init = !!require Fcntl;

    for ( $in, $out ) {
        my $flags = fcntl $_, Fcntl::F_GETFD, 0 or die "fcntl F_GETFD: $!";

        fcntl $_, Fcntl::F_SETFD, $flags & ~Fcntl::FD_CLOEXEC or die "fcntl F_SETFD: $!";
    }

    my $code = $self->_get_code( fileno $in, fileno $out );

    fork && return;    ## no critic qw[InputOutput::RequireCheckedSyscalls]

    exec $^X, '-e', $code or die;
}

sub _get_code ( $self, $fdin, $fdout ) {
    my $code = <<"PERL";
package main v0.1.0;

BEGIN {
    \$0 = '$ENV->{SCRIPT_NAME}';
}

use Pcore;
use Pcore::AE::RPC::Server;

Pcore::AE::RPC::Server->new( { pkg => '@{[$self->pkg]}', in => $fdin, out => $fdout, scan_deps => @{[$self->scan_deps]} } );

1;
PERL

    $code =~ s/\n//smg;

    return $code;
}

sub _store_deps ( $self, $deps ) {
    my $old_deps = -f "$ENV->{DATA_DIR}.pardeps.cbor" ? P->cfg->load("$ENV->{DATA_DIR}.pardeps.cbor") : {};

    my $new_deps;

    for my $pkg ( keys $deps->%* ) {
        if ( !exists $old_deps->{ $ENV->{SCRIPT_NAME} }->{ $Config{archname} }->{$pkg} ) {
            $new_deps = 1;

            say 'new deps found: ' . $pkg;

            $old_deps->{ $ENV->{SCRIPT_NAME} }->{ $Config{archname} }->{$pkg} = $deps->{$pkg};
        }
    }

    P->cfg->store( "$ENV->{DATA_DIR}.pardeps.cbor", $old_deps ) if $new_deps;

    return;
}

sub call ( $self, $method, $data, $cb ) {
    my $call_id = ++$self->{call_id};

    $self->queue->{$call_id} = $cb;

    my $pid = shift $self->next_pid->@*;

    push $self->next_pid->@*, $pid;

    $self->write_data( $self->pid->{$pid}->[1], [ $call_id, $method, $data ] );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 33, 46, 203          │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 98                   │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::RPC

=head1 SYNOPSIS

    my $rpc = Pcore::AE::RPC->new(
        {   pkg      => 'Some::Package',
            on_ready => sub ($self) {
                return;
            }
        }
    );

    $rpc->call(
        'method',
        $data,
        sub ($data) {
            return;
        }
    );

    ...

    package Some::Package;

    sub method ( $self, $cb, $data ) {
        $cb->($result);

        return;
    }

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
