package Pcore::Src::SCM::Hg::Server;

use Pcore -class;
use Pcore::Util::Text qw[decode_utf8];
use Pcore::API::Response;

has root => ( is => 'ro', isa => Str, required => 1 );

has capabilities => ( is => 'ro', isa => Str, init_arg => undef );

has _hg_proc => ( is => 'ro', isa => InstanceOf ['Pcore::Util::PM::Proc'], init_arg => undef );

sub _hg ( $self, $cb = undef ) {
    if ( exists $self->{_hg_proc} ) {
        $cb->( $self->{_hg_proc} ) if $cb;

        return defined wantarray ? $self->{_hg} : ();
    }
    else {
        my $blocking_cv = defined wantarray ? AE::cv : undef;

        my $chdir_guard = P->file->chdir( $self->root ) or die;

        local $ENV{HGENCODING} = 'UTF-8';

        P->pm->run_proc(
            [qw[hg serve --config ui.interactive=True --cmdserver pipe]],
            stdin    => 1,
            stdout   => 1,
            stderr   => 1,
            on_ready => sub ($proc) {
                $self->{_hg_proc} = $proc;

                # read capabilities
                $self->{capabilities} = $self->_read(
                    sub ( $channel, $data ) {
                        $self->{capabilities} = $data;

                        $cb->( $self->{_hg_proc} ) if $cb;

                        $blocking_cv->send( $self->{_hg_proc} ) if $blocking_cv;

                        return;
                    }
                );

                return;
            }
        );

        return $blocking_cv ? $blocking_cv->recv : ();
    }
}

sub _read ( $self, $cb ) {
    $self->_hg(
        sub($hg) {
            $hg->stdout->push_read(
                chunk => 5,
                sub ( $h, $data ) {
                    my $channel = substr $data, 0, 1, q[];

                    $h->push_read(
                        chunk => unpack( 'L>', $data ),
                        sub ( $h, $data ) {
                            $cb->( $channel, $data );

                            return;
                        }
                    );

                    return;
                }
            );

            return;
        }
    );

    return;
}

# NOTE status + pattern (status *.txt) not works under linux - http://bz.selenic.com/show_bug.cgi?id=4526
sub cmd ( $self, @cmd ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $cb = ref $cmd[-1] eq 'CODE' ? pop @cmd : undef;

    my $buf = join qq[\x00], @cmd;

    $buf = Encode::encode( $Pcore::WIN_ENC, $buf, Encode::FB_CROAK );

    my $cmd = qq[runcommand\x0A] . pack( 'L>', length $buf ) . $buf;

    $self->_hg(
        sub ($hg) {
            $hg->stdin->push_write($cmd);

            my $res = {};

            my $read = sub ( $channel, $data ) {
                if ( $channel ne 'r' ) {
                    chomp $data;

                    decode_utf8( $data, encoding => $Pcore::WIN_ENC );

                    push $res->{$channel}->@*, $data;

                    $self->_read(__SUB__);
                }
                else {
                    my $api_res = Pcore::API::Response->new( { status => 200 } );

                    if ( exists $res->{e} ) {
                        $api_res->set_status( 500, join q[ ], $res->{e}->@* );
                    }
                    else {
                        $api_res->{result} = $res->{o};
                    }

                    $cb->($api_res) if $cb;

                    $blocking_cv->($api_res) if $blocking_cv;
                }

                return;
            };

            $self->_read($read);

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 89, 93               │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
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
