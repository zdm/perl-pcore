package Pcore::Util::Path1::Poll;

use Pcore -role, -const;

our $POLL;
our $POLL_THREAD;
our $POLL_TIMEOUT = 3;

sub poll ( $self, @ ) {
    my $cb = is_plain_coderef $_[-1] ? shift : ();

    if ($cb) {
        $POLL->{$self}->{ refaddr $cb } = $cb;
    }

    _poll_path($self);

    _poll_run_thread() if !$POLL_THREAD;

    return;
}

sub _poll_path ($path) {
    $path->stat;

    if ( -d $path ) {

    }

    IO::AIO::aio_stat(
        "$path",
        sub ($error) {

            # die if $error;

            # my $mtime = IO::AIO::st_mtime;

            # if ( !exists $files->{$path} || $files->{$path} != $mtime ) {
            #     $files->{$path} = $mtime;

            #     $changed = 1;
            # }

            # $cv->end;

            return;
        }
    );

    return;
}

sub _poll_run_thread {
    $POLL_THREAD = 1;

    Coro::async {
        while () {
            Coro::AnyEvent::sleep $POLL_TIMEOUT;
        }

        return;
    };

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path1::Poll

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
