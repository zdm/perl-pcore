package Pcore::AE::RPC;

use Pcore -class;
use AnyEvent::Util qw[portable_socketpair];

with qw[Pcore::AE::RPC::Base];

has on_ready => ( is => 'ro', isa => CodeRef );

has pid => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has call_id => ( is => 'ro', default => 0, init_arg => undef );
has queue => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );
has next_pid => ( is => 'lazy', isa => ArrayRef, init_arg => undef );

# TODO
# pass fh via system FH num;
# test under linux;
# run from PAR;

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

sub _run_server ( $self, $ready ) {
    $ready->begin;

    my $CODE = <<"PERL";
package main v0.1.0;

BEGIN {
    \$0 = 'aerpc.pl';
}

use Pcore;
use Pcore::AE::RPC::Server;

Pcore::AE::RPC::Server->new( { pkg => '@{[$self->pkg]}' } );

1;
PERL

    my ( $in1, $out )  = portable_socketpair();
    my ( $in,  $out1 ) = portable_socketpair();

    $in->autoflush(1);
    $out->autoflush(1);

    # store old STD* handles
    open my $old_in,  '<&', *STDIN  or die;    ## no critic qw[InputOutput::RequireBriefOpen]
    open my $old_out, '>&', *STDOUT or die;    ## no critic qw[InputOutput::RequireBriefOpen]

    # redirect STD* handles
    open STDIN,  '<&', $in1  or die;
    open STDOUT, '>&', $out1 or die;

    # spawn hg command server
    {
        my $chdir_guard = P->file->chdir( $ENV->{SCRIPT_DIR} ) or die;

        $CODE =~ s/\n//smg;

        if ($MSWIN) {
            state $init = !!require Win32::Process;

            Win32::Process::Create(    #
                my $obj,
                $ENV{COMSPEC},
                qq[/D /C $^X -e "$CODE"],
                1,
                0,                     # WARNING: not works if not 0, Win32::Process::CREATE_NO_WINDOW(),
                q[.]
            ) || die $!;

            $self->{_pid} = $obj;
        }
        else {
            system( $^X, '-e', $CODE ) or 1;
        }
    }

    # close child handles
    close $in1  or die;
    close $out1 or die;

    # restore STD* handles
    open STDIN,  '<&', $old_in  or die;
    open STDOUT, '>&', $old_out or die;

    my $pid;

    my $cv = AE::cv {
        $self->pid->{$pid} = [ $in, $out ];

        $self->start_listen(
            $in,
            sub ($data) {
                if ( my $cb = delete $self->queue->{ $data->[0] } ) {
                    $cb->( $data->[1] );
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
## │    3 │ 35, 48               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 145                  │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 104                  │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::RPC

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
