package Pcore::AE::RPC::Server;

use Pcore -class;

with qw[Pcore::AE::RPC::Base];

has obj => ( is => 'lazy', isa => Object, init_arg => undef );
has in  => ( is => 'ro',   isa => Object, init_arg => undef );
has out => ( is => 'ro',   isa => Object, init_arg => undef );

sub BUILD ( $self, $args ) {
    my $cv = AE::cv;

    $cv->begin;
    Pcore::AE::Handle->new(
        fh         => \*STDIN,
        on_connect => sub ( $h, @ ) {
            $self->{in} = $h;

            $cv->end;

            return;
        }
    );

    $cv->begin;
    Pcore::AE::Handle->new(
        fh         => \*STDOUT,
        on_connect => sub ( $h, @ ) {
            $self->{out} = $h;

            $cv->end;

            return;
        }
    );

    $cv->recv;

    # handshake, send PID
    $self->out->push_write("READY$$\x00");

    $self->start_listen(
        $self->in,
        sub ($req) {
            my $call_id = $req->[0];

            my $method = $req->[1];

            $self->obj->$method(
                sub ($res) {
                    $self->write_data( $self->out, [ $call_id, $res ] );

                    return;
                },
                $req->[2],
            );

            return;
        }
    );

    P->cv->recv;

    exit;
}

sub _build_obj ($self) {
    return P->class->load( $self->pkg )->new;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 41                   │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::RPC::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
