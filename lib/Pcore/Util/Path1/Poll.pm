package Pcore::Util::Path1::Poll;

use Pcore -role, -const;
use Pcore::Util::Scalar qw[is_plain_coderef];
use Time::HiRes qw[];
use Coro::Signal qw[];

const our $DEFAULT_POLL_INTERVAL => 3;

sub poll ( $self, @ ) {
    state $POLL_INTERVAL = $DEFAULT_POLL_INTERVAL;
    state $POLL;
    state $SIGNAL = Coro::Signal->new;
    state $thread;

    my $cb = is_plain_coderef $_[-1] ? pop : ();

    my %args = @_[ 1 .. $#_ ];

    my $interval = $args{interval} || $DEFAULT_POLL_INTERVAL;

    my $path = $self->to_abs;

    my $poll = $POLL->{$path} = {
        path     => $path,
        interval => $interval,
        last     => 0,
        cb       => $cb,
    };

    $POLL_INTERVAL = $interval if $interval < $POLL_INTERVAL;

    if ( -e $path ) {
        $poll->{stat}->{$path} = [ Time::HiRes::stat($path) ];

        if ( -d _ && ( my $files = $path->read_dir( abs => 1, recursive => 1, dir => 0 ) ) ) {
            for my $file ( $files->@* ) {
                $poll->{stat}->{$file} = [ Time::HiRes::stat($file) ];
            }
        }
    }

    if ($thread) {
        $SIGNAL->send if $SIGNAL->awaited;

        return;
    }

    $thread = Coro::async {
        while () {
            Coro::AnyEvent::sleep $POLL_INTERVAL;

            for my $poll ( values $POLL->%* ) {
                next if $poll->{last} + $poll->{interval} > time;

                $poll->{last} = time;

                say $poll->{path};

                my $stat;

                if ( -e $poll->{path} ) {
                    $stat->{ $poll->{path} } = [ Time::HiRes::stat $poll->{path} ];

                    if ( -d _ && ( my $files = $poll->{path}->read_dir( abs => 1, recursive => 1, dir => 0 ) ) ) {
                        for my $file ( $files->@* ) {
                            $stat->{$file} = [ Time::HiRes::stat($file) ];
                        }
                    }
                }

                my @changes;

                for my $file ( keys $stat->%* ) {
                    if ( exists $poll->{stat}->{$file} ) {
                        push @changes, [ $file, 'modified' ] if $poll->{stat}->{$file}->[9] != $stat->{$file}->[9];
                    }
                    else {
                        push @changes, [ $file, 'created' ];
                    }

                    $poll->{stat}->{$file} = $stat->{$file};
                }

                for my $file ( keys $poll->{stat}->%* ) {
                    if ( !exists $stat->{$file} ) {
                        delete $poll->{stat}->{$file};

                        push @changes, [ $file, 'removed' ];
                    }
                }

                $poll->{cb}->( \@changes ) if @changes;
            }

            $SIGNAL->wait if !$POLL->%*;
        }
    };

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 10                   | Subroutines::ProhibitExcessComplexity - Subroutine "poll" with high complexity score (25)                      |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
