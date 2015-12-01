package Pcore::Util::File::TempFile;

use Pcore qw[-const];
use base qw[IO::Handle IO::Seekable];
use Fcntl qw[:DEFAULT];

use overload    #
  q[""] => sub {
    return $_[0]->path;
  },
  fallback => undef;

const our $TMPL => [ 0 .. 9, 'a' .. 'z', 'A' .. 'Z' ];

no Pcore;

sub new ( $self, @ ) {
    my %args = (
        base      => $PROC->{TEMP_DIR},
        suffix    => q[],
        tmpl      => 'temp-' . P->sys->pid . '-XXXXXXXX',
        mode      => 'rw-------',
        umask     => undef,
        crlf      => 0,                                     # undef - auto, 1 - on, 0 - off (for binary files)
        binmode   => undef,
        autoflush => 1,
        @_[ 1 .. $#_ ]
    );

    P->file->mkpath( $args{base} ) if !-e $args{base};

    my $attempt = 3;

  REDO:
    die q[Can't create temporary file] if !$attempt--;

    my $filename = $args{tmpl} =~ s/X/$TMPL->[rand $TMPL->@*]/smger . $args{suffix};

    goto REDO if -e $args{base} . q[/] . $filename;

    my $fh = P->file->get_fh( $args{base} . q[/] . $filename, O_CREAT | O_EXCL | O_RDWR, %args );

    *$fh->$* = [ P->path( $args{base} . q[/] . $filename )->realpath, P->sys->pid ];    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return bless $fh, $self;
}

sub DESTROY ($self) {

    # do not unlink files, create by others processes
    return if $self->pid ne P->sys->pid;

    close $self or 1;

    unlink $self->path or 1;

    return;
}

sub path ($self) {
    return *$self->$*->[0];
}

sub pid ($self) {
    return *$self->$*->[1];
}

sub TO_DUMP ( $self, $dumper, @ ) {
    my %args = (
        path => undef,
        @_[ 2 .. $#_ ]
    );

    my $res;
    my $tags;

    $res .= $dumper->_dump_blessed( $self, path => $args{path} );
    $res .= qq[,\npath: "] . $self->path . q["];

    return $res, $tags;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 43, 61, 65           │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 18                   │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File::TempFile

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
