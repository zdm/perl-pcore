package Pcore::LogChannel::Console;

use Pcore qw[-class];
use Term::ANSIColor qw[:constants];

with qw[Pcore::Core::Log::Channel];

has '+header' => ( default => sub { BOLD GREEN . '[%H:%M:%S.%6N]' . BOLD CYAN . '[%ID]' . BOLD YELLOW . '[%NS]' . BOLD RED . '[%LEVEL]' . RESET } );
has '+priority' => ( default => 2 );
has '+color'    => ( default => 1 );

sub send_log {
    my $self = shift;
    my %args = @_;

    for my $i ( 0 .. $#{ $args{data} } ) {
        print {$STDERR_UTF8} $args{header} . q[ ] if $args{header};

        say {$STDERR_UTF8} $args{data}->[$i];
    }

    return 1;
}

1;
__END__
=pod

=encoding utf8

=cut
