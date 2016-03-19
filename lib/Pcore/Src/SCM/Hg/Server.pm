package Pcore::Src::SCM::Hg::Server;

use Pcore -class;
use Pcore::Util::Text qw[decode_utf8];

has root => ( is => 'ro', isa => Str, required => 1 );

has _hg => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::PM::Proc'], init_arg => undef );
has capabilities => ( is => 'ro', isa => Str, init_arg => undef );

sub _build__hg ($self) {
    my $chdir_guard = P->file->chdir( $self->root ) or die;

    local $ENV{HGENCODING} = 'UTF-8';

    my $cv = AE::cv;

    P->pm->run_proc(
        [qw[hg serve --config ui.interactive=True --cmdserver pipe]],
        stdin    => 1,
        stdout   => 1,
        stderr   => 1,
        on_ready => sub ($proc) {
            $self->{_hg} = $proc;

            $cv->send;

            return;
        }
    );

    $cv->recv;

    # read capabilities
    $self->{capabilities} = $self->_read;

    return $self->{_hg};
}

sub _read ($self) {
    my $cv = AE::cv;

    my ( $channel, $msg );

    $self->_hg->stdout->push_read(
        chunk => 5,
        sub ( $h, $data ) {
            $channel = substr $data, 0, 1, q[];

            $h->push_read(
                chunk => unpack( 'L>', $data ),
                sub ( $h, $data ) {
                    $msg = $data;

                    $cv->send;

                    return;
                }
            );

            return;
        }
    );

    $cv->recv;

    return $channel, $msg;
}

# NOTE status + pattern (status *.txt) not works under linux - http://bz.selenic.com/show_bug.cgi?id=4526
sub cmd ( $self, @cmd ) {
    my $buf = join qq[\x00], @cmd;

    $buf = Encode::encode( $Pcore::WIN_ENC, $buf, Encode::FB_CROAK );

    my $cmd = qq[runcommand\x0A] . pack( 'L>', length $buf ) . $buf;

    $self->_hg->stdin->push_write($cmd);

    my $res = {};

  READ_CHUNK:
    my ( $channel, $data ) = $self->_read;

    if ( $channel ne 'r' ) {
        chomp $data;

        decode_utf8( $data, encoding => $Pcore::WIN_ENC );

        push $res->{$channel}->@*, $data;

        goto READ_CHUNK;
    }

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 72, 76               │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
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
