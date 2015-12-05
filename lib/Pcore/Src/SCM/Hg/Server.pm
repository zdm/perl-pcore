package Pcore::Src::SCM::Hg::Server;

use Pcore qw[-class];
use AnyEvent::Util qw[portable_socketpair];

has root => ( is => 'ro', isa => Str, required => 1 );

has capabilities => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has _in  => ( is => 'ro', init_arg => undef );    # read from child
has _out => ( is => 'ro', init_arg => undef );    # write to child
has _pid => ( is => 'ro', init_arg => undef );

no Pcore;

sub BUILD ( $self, $args ) {
    ( my $in_r, $self->{_out} ) = portable_socketpair();

    ( $self->{_in}, my $out_w ) = portable_socketpair();

    $in_r->autoflush(1);
    $self->{_in}->autoflush(1);
    $self->{_out}->autoflush(1);
    $out_w->autoflush(1);

    # store old STD* handles
    open my $old_in,  '<&', *STDIN  or die;    ## no critic qw[InputOutput::RequireBriefOpen]
    open my $old_out, '>&', *STDOUT or die;    ## no critic qw[InputOutput::RequireBriefOpen]

    # redirect STD* handles
    open STDIN,  '<&', $in_r  or die;
    open STDOUT, '>&', $out_w or die;

    # spawn hg command server
    {
        my $chdir_guard = P->file->chdir( $self->root ) or die;

        local $ENV{HGENCODING} = 'UTF-8';

        if ($MSWIN) {
            require Win32::Process;

            Win32::Process::Create(    #
                $self->{_pid},
                $ENV{COMSPEC},
                '/D /C hg serve --config ui.interactive=True --cmdserver pipe',
                1,
                0,                     # CREATE_NEW_CONSOLE, # CREATE_NO_WINDOW,
                q[.]
            ) || die;
        }
        else {
            exec 'hg serve --config ui.interactive=True --cmdserver pipe' or die unless fork;
        }
    }

    # close child handles
    close $in_r  or die;
    close $out_w or die;

    # restore STD* handles
    open STDIN,  '<&', $old_in  or die;
    open STDOUT, '>&', $old_out or die;

    # read capabilities
    my ( $ch, $data ) = $self->_read_chunk;

    $self->{capabilities} = $data;

    # parse real hg PID from the header
    ( $self->{_pid} ) = $self->{capabilities} =~ /pid:\s*(\d+)/sm;

    return;
}

sub DEMOLISH ( $self, $global ) {
    close $self->_in or die;

    close $self->_out or die;

    if ($MSWIN) {
        Win32::Process::KillProcess( $self->_pid, 0 ) if $self->_pid;
    }
    else {
        kill 9, $self->_pid or 1 if $self->_pid;
    }

    return;
}

# NOTE status + pattern (status *.txt) not works under linux - http://bz.selenic.com/show_bug.cgi?id=4526
sub cmd ( $self, @cmd ) {
    my $buf = join qq[\x00], @cmd;

    $buf = Encode::encode( $Pcore::WIN_ENC, $buf, Encode::FB_CROAK );

    my $cmd = qq[runcommand\x0A] . pack( 'L>', length $buf ) . $buf;

    syswrite $self->_out, $cmd or die;

    my $res = {};

  READ_CHUNK:
    my ( $channel, $data ) = $self->_read_chunk;

    if ( $channel ne 'r' ) {
        chomp $data;

        P->text->decode( $data, encoding => $Pcore::WIN_ENC );

        push $res->{$channel}->@*, $data;

        goto READ_CHUNK;
    }

    return $res;
}

sub _read_chunk ($self) {
    sysread $self->_in, my $header, 5, 0 or die;

    my $channel = substr $header, 0, 1, q[];

    my $len = unpack 'L>', $header;

    sysread $self->_in, my $data, $len, 0 or die;

    return $channel => $data;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 93, 97               │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::SCM::Hg::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
