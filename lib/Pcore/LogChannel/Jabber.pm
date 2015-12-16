package Pcore::LogChannel::Jabber;

use Pcore -class;

with qw[Pcore::Core::Log::Channel];

has '+stream'   => ( required => 1 );
has '+header'   => ( default  => '[%H:%M:%S.%6N][%ID][%NS][%LEVEL]' );
has '+priority' => ( default  => 3 );

sub send_log {
    my $self = shift;
    my %args = @_;

    my $packet = [];

    for my $i ( 0 .. $#{ $args{data} } ) {
        my $message = q[];
        $message .= $args{header} . $LF if $args{header};
        $message .= $args{data}->[$i];
        push @{$packet}, { to => $self->stream, message => $mesage };
    }
    H->JABBER->send($packet);

    return 1;
}

1;
__END__
=pod

=encoding utf8

=cut
