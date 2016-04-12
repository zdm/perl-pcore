package Pcore::API::SCM::Server::Mercurial;

use Pcore -class;
use Pcore::Util::Text qw[decode_utf8];
use Pcore::API::Response;
use Pcore::Util::Scalar qw[weaken];

with qw[Pcore::API::SCM::Server];

has capabilities => ( is => 'ro', isa => Str, init_arg => undef );

has _server_proc => ( is => 'ro', isa => InstanceOf ['Pcore::Util::PM::Proc'], init_arg => undef );

our $SERVER_PROC;

sub _server ( $self, $cb ) {
    if ( exists $self->{_server_proc} ) {
        $cb->( $self->{_server_proc} );

        return;
    }
    elsif ($SERVER_PROC) {
        $self->{_server_proc} = $SERVER_PROC;

        $cb->( $self->{_server_proc} );

        return;
    }
    else {
        local $ENV{HGENCODING} = 'UTF-8';

        P->pm->run_proc(
            [qw[hg serve --config ui.interactive=True --cmdserver pipe]],
            stdin    => 1,
            stdout   => 1,
            stderr   => 1,
            on_ready => sub ($proc) {
                $self->{_server_proc} = $proc;

                $SERVER_PROC = $proc;

                weaken $SERVER_PROC;

                # read capabilities
                $self->{capabilities} = $self->_read(
                    sub ( $channel, $data ) {
                        $self->{capabilities} = $data;

                        $cb->( $self->{_server_proc} );

                        return;
                    }
                );

                return;
            }
        );

        return;
    }
}

sub _read ( $self, $cb ) {
    $self->_server(
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
sub scm_cmd ( $self, $root, $cb, $cmd ) {
    my $buf = join qq[\x00], $cmd->@*;

    $buf .= "\x00--repository\x00$root" if $root;

    $buf = Encode::encode( $Pcore::WIN_ENC, $buf, Encode::FB_CROAK );

    $self->_server(
        sub ($hg) {
            $hg->stdin->push_write( qq[runcommand\x0A] . pack( 'L>', length $buf ) . $buf );

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

                    $cb->($api_res);
                }

                return;
            };

            $self->_read($read);

            return;
        }
    );

    return;
}

sub scm_init ( $self, $root, $cb, $args ) {
    $self->scm_cmd( $root, $cb, [qw[init]] );

    return;
}

sub scm_clone ( $self, $root, $cb, $args ) {
    my ( $url, %args ) = $args->@*;

    my @cmd = qw[clone];

    push @cmd, '--updaterev', $args{tag} if $args{tag};

    push @cmd, $url, $root;

    $self->scm_cmd( undef, $cb, \@cmd );

    return;
}

sub scm_releases ( $self, $root, $cb, $args ) {
    $self->scm_cmd(
        $root,
        sub ($res) {
            if ( $res->is_success ) {
                $res->{result} = { map { $_ => undef } grep {/\Av\d+[.]\d+[.]\d+\z/sm} $res->{result}->@* };
            }

            $cb->($res);

            return;
        },
        [qw[tags --template {tag}]]
    );

    return;
}

sub scm_latest_tag ( $self, $root, $cb, $args ) {
    $self->scm_cmd(
        $root,
        sub ($res) {
            if ( $res->is_success ) {
                $res->{result} = { map { split /\x00/sm } $res->{result}->@* };
            }

            $cb->($res);

            return;
        },
        [ qw[log -r . --template], q[{latesttag('re:^v\d+[.]\d+[.]\d+$') % '{tag}\x00{distance}'}] ]
    );

    return;
}

sub scm_is_commited ( $self, $root, $cb, $args ) {
    $self->scm_cmd(
        $root,
        sub ($res) {
            if ( $res->is_success ) {
                $res->{result} = defined $res->{result} ? 0 : 1;
            }

            $cb->($res);

            return;
        },
        [qw[status -mardu --subrepos]]
    );

    return;
}

sub scm_addremove ( $self, $root, $cb, $args ) {
    $self->scm_cmd( $root, $cb, [qw[addremove --subrepos]] );

    return;
}

sub scm_commit ( $self, $root, $cb, $args ) {
    my $message = $args->[0];

    $self->scm_cmd( $root, $cb, [ qw[commit --subrepos -m], $message ] );

    return;
}

sub scm_push ( $self, $root, $cb, $args ) {
    $self->scm_cmd( $root, $cb, [qw[push]] );

    return;
}

sub scm_set_tag ( $self, $root, $cb, $args ) {
    my ( $tag, %args ) = $args->@*;

    $tag = [$tag] if !ref $tag;

    my @cmd = ( 'tag', $tag->@* );

    push @cmd, '--force' if $args{force};

    $self->scm_cmd( $root, $cb, \@cmd );

    return;
}

sub scm_branch ( $self, $root, $cb, $args ) {
    $self->scm_cmd(
        $root,
        sub ($res) {
            if ( $res->is_success ) {
                $res->{result} = $res->{result}->[0];
            }

            $cb->($res);

            return;
        },
        [qw[branch]]
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
## │    2 │ 93, 95, 101          │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 190                  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::SCM::Server::Mercurial

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
