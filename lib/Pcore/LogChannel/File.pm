package Pcore::LogChannel::File;

use Pcore -class;
use IO::File;
use Fcntl qw[:flock];

with qw[Pcore::Core::Log::Channel];

has '+stream'   => ( required => 1 );
has '+header'   => ( default  => '[%Y-%m-%d %H:%M:%S.%6N][%ID][%NS][%LEVEL]' );
has '+priority' => ( default  => 1 );
has h           => ( is       => 'lazy', isa => Str, init_arg => undef );

sub _build_h {
    my $self = shift;

    my $h = $PROC->{LOG_DIR} . $self->stream;

    H->add(
        $h        => 'File',
        path      => $h,
        binmode   => ':encoding(UTF-8)',
        autoflush => 1
    );

    return $h;
}

sub send_log {
    my $self = shift;
    my %args = @_;

    return unless $PROC->{LOG_DIR};

    my $stream = $self->h;

    my $h = H->$stream->h;

    for my $i ( 0 .. $args{data}->$#* ) {
        flock $h, LOCK_EX or die;

        $h->print( $args{header} . q[ ] ) if $args{header};

        $h->say( $args{data}->[$i] );

        flock $h, LOCK_UN or die;
    }

    return 1;
}

1;
__END__
=pod

=encoding utf8

=cut
