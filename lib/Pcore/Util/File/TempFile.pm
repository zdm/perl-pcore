package Pcore::Util::File::TempFile;

use Pcore -const;
use base qw[IO::Handle IO::Seekable];
use Fcntl qw[:DEFAULT];
use Scalar::Util qw[refaddr];    ## no critic qw[Modules::ProhibitEvilModules]

use overload                     #
  q[""] => sub {
    return $_[0]->path;
  },
  q[cmp] => sub {
    return !$_[2] ? $_[0]->path cmp $_[1] : $_[1] cmp $_[0]->path;
  },
  q[0+] => sub {
    return refaddr $_[0];
  },
  fallback => undef;

const our $TMPL => [ 0 .. 9, 'a' .. 'z', 'A' .. 'Z' ];

our @DEFERRED_UNLINK;

no Pcore;

END {
    for (@DEFERRED_UNLINK) {
        unlink or 1;
    }
}

sub new ( $self, @ ) {
    my %args = (
        base      => $ENV->{TEMP_DIR},
        suffix    => q[],
        tmpl      => 'temp-' . P->sys->pid . '-XXXXXXXX',
        exclusive => 0,
        mode      => 'rw-------',
        umask     => undef,
        crlf      => 0,                                     # undef - auto, 1 - on, 0 - off (for binary files)
        binmode   => undef,
        autoflush => 1,
        @_[ 1 .. $#_ ]
    );

    $args{suffix} = q[.] . $args{suffix} if defined $args{suffix} && $args{suffix} ne q[] && substr( $args{suffix}, 0, 1 ) ne q[.];

    P->file->mkpath( $args{base} ) if !-e $args{base};

    my $attempt = 3;

  REDO:
    die q[Can't create temporary file] if !$attempt--;

    my $filename = $args{tmpl} =~ s/X/$TMPL->[rand $TMPL->@*]/smger . $args{suffix};

    goto REDO if -e $args{base} . q[/] . $filename;

    my $mode = O_CREAT | O_EXCL | O_RDWR;    # O_TEMPORARY - not defined under Linux;

    $mode |= O_EXLOCK if $args{exclusive};

    my $fh = P->file->get_fh( $args{base} . q[/] . $filename, $mode, %args );

    *$fh->$* = [ P->path( $args{base} . q[/] . $filename )->realpath->to_string, P->sys->pid ];    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return bless $fh, $self;
}

# TODO
# need to ensure, that path and fh is the same when unlink, see File::Temp::cmpstat method
sub DESTROY ($self) {

    # do not unlink files, created by others processes
    return if $self->pid ne P->sys->pid;

    close $self or 1;

    unlink $self->path or 1;

    push @DEFERRED_UNLINK, $self->path if -f $self->path;

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
## │    3 │ 65, 87, 91           │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 33                   │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
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
