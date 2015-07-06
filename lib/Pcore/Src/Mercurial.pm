package Pcore::Src::Mercurial;

use Pcore qw[-class];
use IPC::Run qw[];
use Pcore::Src::Mercurial::File;

has source => ( is => 'ro', isa => Str, required => 1 );

has root => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::File::Path'], init_arg => undef );

has _hg => ( is => 'lazy', isa => InstanceOf ['IPC::Run'], predicate => 1, clearer => 1, init_arg => undef );
has _in  => ( is => 'rwp', isa => FileHandle, clearer => 1, init_arg => undef );
has _out => ( is => 'rwp', isa => FileHandle, clearer => 1, init_arg => undef );
has _err => ( is => 'rwp', isa => FileHandle, clearer => 1, init_arg => undef );
has _capabilities => ( is => 'rwp', isa => HashRef, default => sub { {} }, clearer => 1, init_arg => undef );

no Pcore;

sub _build__hg {
    my $self = shift;

    my $hg;

    my $in = \*_HG_IN;

    my $out = \*_HG_OUT;

    my $err = \*_HG_ERR;

    {
        my $chdir_guard = P->file->chdir( $self->source ) or die;

        local $ENV{HGENCODING} = 'UTF-8';

        $hg = IPC::Run::start( [qw[hg --config ui.interactive=True serve --cmdserver pipe]], '<pipe', IPC::Run::binary, $in, '>pipe', IPC::Run::binary, $out, '2>pipe', $err ) or die;
    }

    $in->autoflush(1);
    $out->autoflush(1);
    $err->autoflush(1);

    $self->_set__in($in);
    $self->_set__out($out);
    $self->_set__err($err);

    # read capabilities
    my ( $channel, $data ) = $self->_read_chunk;

    for my $str ( split /\x0A/sm, $data ) {
        my ( $key, $val ) = $str =~ /\A(.+)?:(.*)\z/sm;

        $self->_capabilities->{$key} = $val;

        if ( $key eq 'capabilities' ) {
            $self->_capabilities->{$key} = {};

            for ( grep {$_} split /\s/sm, $val ) {
                $self->_capabilities->{$key}->{$_} = 1;
            }
        }
    }

    return $hg;
}

sub _build_root {
    my $self = shift;

    my $res = $self->hg_cmd('root');

    if ( $res->{e} ) {
        die 'No repo at this path';
    }
    else {
        return P->file->path( $res->{o}->[0], is_dir => 1 )->realpath;
    }
}

sub disconnect {
    my $self = shift;

    if ( $self->_has_hg ) {
        $self->_in->close if $self->_in;

        $self->_out->close if $self->_out;

        $self->_err->close if $self->_err;

        $self->_clear_in;

        $self->_clear_out;

        $self->_clear_err;

        IPC::Run::finish( $self->_hg );

        $self->_clear_capabilities;
    }

    return;
}

sub DEMOLISH {
    my $self = shift;

    $self->disconnect;

    return;
}

sub _read_chunk {
    my $self = shift;

    sysread $self->_out, my $header, 5, 0 or die;

    my $channel = substr $header, 0, 1, q[];

    my $len = unpack 'L>', $header;

    sysread $self->_out, my $data, $len, 0 or die;

    return $channel => $data;
}

# NOTE
# status + pattern (status *.txt) not works under linux - http://bz.selenic.com/show_bug.cgi?id=4526
sub hg_cmd {
    my $self = shift;
    my @cmd  = @_;

    # connect to server
    $self->_hg;

    my $buff = join qq[\x00], @cmd;

    my $cmd = qq[runcommand\x0A] . pack( 'L>', length $buff ) . $buff;

    syswrite $self->_in, $cmd or die;

    my $res = {};

  READ_CHUNK:
    my ( $channel, $data ) = $self->_read_chunk;

    if ( $channel ne 'r' ) {
        chomp $data;

        P->text->decode( $data, stdin => 1 );

        push $res->{$channel}->@*, $data;

        goto READ_CHUNK;
    }

    return $res;
}

# pre-commit hook
sub hg_pre_commit {
    my $self = shift;

    my $hg_opts = P->data->from_json( P->text->decode( $ENV{HG_OPTS_JSON}, stdin => 1 )->$*, utf8 => 0 );

    my $options = {};

    $options->{include} = $hg_opts->{include} if $hg_opts->{include};

    $options->{exclude} = $hg_opts->{exclude} if $hg_opts->{exclude};

    my $cmd = $self->_prepare_cmd( $options, scalar P->data->from_json( P->text->decode( $ENV{HG_PATS_JSON}, stdin => 1 )->$*, utf8 => 0 ) );

    unshift $cmd->@*, 'status';

    my $res = $self->hg_cmd( $cmd->@* );

    die $res->{e}->@* if $res->{e};

    my $commit;

    $commit->{message} = $hg_opts->{message};

    $commit->{files} = [];

    for my $pair ( P->list->pairs( $res->{o}->@* ) ) {
        P->text->trim( $pair->[0] );

        push $commit->{files}->@*, Pcore::Src::Mercurial::File->new( { path => P->file->path( $pair->[1], base => $self->root ), status => $pair->[0] } );
    }

    return $commit;
}

sub _prepare_cmd {
    my $self = shift;

    my @cmd;

    for my $arg ( grep {$_} @_ ) {
        if ( ref $arg eq 'HASH' ) {
            for my $key ( sort grep { $arg->{$_} } keys $arg ) {
                if ( ref $arg->{$key} eq 'ARRAY' ) {
                    for my $val ( $arg->{$key}->@* ) {
                        push @cmd, qq[--$key], $val;
                    }
                }
                else {
                    push @cmd, qq[--$key], $arg->{$key};
                }
            }
        }
        elsif ( ref $arg eq 'ARRAY' ) {
            for my $val ( grep {$_} $arg->@* ) {
                push @cmd, $val;
            }
        }
        else {
            push @cmd, $arg;
        }
    }

    for (@cmd) {
        P->text->encode_stdout($_);
    }

    return \@cmd;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 134, 136             │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::Mercurial

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
