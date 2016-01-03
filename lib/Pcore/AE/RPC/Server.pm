package Pcore::AE::RPC::Server;

use Pcore -class;

with qw[Pcore::AE::RPC::Base];

has obj => ( is => 'lazy', isa => Object, init_arg => undef );
has in  => ( is => 'ro',   isa => Object, init_arg => undef );
has out => ( is => 'ro',   isa => Object, init_arg => undef );

sub BUILD ( $self, $args ) {
    if ($MSWIN) {
        require Win32API::File;

        Win32API::File::OsFHandleOpen( *RPC_IN,  $args->{in},  'r' ) or die $!;
        Win32API::File::OsFHandleOpen( *RPC_OUT, $args->{out}, 'w' ) or die $!;
    }
    else {
        open *RPC_IN,  '<&=', $args->{in}  or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
        open *RPC_OUT, '>&=', $args->{out} or die $!;    ## no critic qw[InputOutput::RequireBriefOpen]
    }

    my $cv = AE::cv;

    $cv->begin;
    Pcore::AE::Handle->new(
        fh         => \*RPC_IN,
        on_connect => sub ( $h, @ ) {
            $self->{in} = $h;

            $cv->end;

            return;
        }
    );

    $cv->begin;
    Pcore::AE::Handle->new(
        fh         => \*RPC_OUT,
        on_connect => sub ( $h, @ ) {
            $self->{out} = $h;

            $cv->end;

            return;
        }
    );

    $cv->recv;

    # handshake, send PID
    $self->out->push_write("READY$$\x00");

    my $deps = {};

    $self->start_listen(
        $self->in,
        sub ($req) {
            my $call_id = $req->[0];

            my $method = $req->[1];

            $self->obj->$method(
                sub ($res = undef) {

                    # make PAR deps snapshot after each call
                    my $new_deps;

                    if ( $args->{scan_deps} ) {
                        for my $pkg ( grep { !exists $deps->{$_} } keys %INC ) {
                            $new_deps = 1;

                            $deps->{$pkg} = $INC{$pkg};
                        }
                    }

                    $self->write_data( $self->out, [ $new_deps ? $deps : undef, $call_id, $res ] );

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
## │    2 │ 52                   │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
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
