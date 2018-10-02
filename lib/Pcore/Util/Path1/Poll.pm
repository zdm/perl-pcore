package Pcore::Util::Path1::Poll;

use Pcore -role, -const, -export;
use Pcore::Util::Scalar qw[is_plain_coderef];
use Time::HiRes qw[];
use Coro::Signal qw[];

const our $DEFAULT_POLL_INTERVAL => 3;

const our $POLL_CREATED  => 1;
const our $POLL_MODIFIED => 2;
const our $POLL_REMOVED  => 3;

our $EXPORT = { POLL => [qw[$POLL_CREATED $POLL_MODIFIED $POLL_REMOVED]] };

# interval - poll interval
# root - check and report root path itself
# abs - return absolute or relative paths
# recursive - scan root path recursive
# dir - report dirs
# files - report files
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
        path      => $path,
        interval  => $interval,
        last      => 0,
        cb        => $cb,
        root      => $args{root},
        abs       => $args{abs},
        recursive => $args{recursive},
        dir       => $args{dir},
        file      => $args{file},
    };

    $POLL_INTERVAL = $interval if $interval < $POLL_INTERVAL;

    # initial scan
    if ( -e $path ) {
        $poll->{stat}->{$path} = [ Time::HiRes::stat($path) ] if $poll->{root};

        if ( -d _ && ( my $files = $path->read_dir( abs => 1, recursive => $poll->{recursive}, dir => $poll->{dir}, file => $poll->{file} ) ) ) {
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
                    $stat->{ $poll->{path} } = [ Time::HiRes::stat $poll->{path} ] if $poll->{root};

                    if ( -d _ && ( my $files = $poll->{path}->read_dir( abs => 1, recursive => $poll->{recursive}, dir => $poll->{dir}, file => $poll->{file} ) ) ) {
                        for my $file ( $files->@* ) {
                            $stat->{$file} = [ Time::HiRes::stat($file) ];
                        }
                    }
                }

                my @changes;

                my $root_len = $poll->{abs} ? undef : 1 + length $poll->{path};

                for my $file ( keys $stat->%* ) {
                    if ( exists $poll->{stat}->{$file} ) {
                        push @changes, [ $poll->{abs} ? $file : substr( $file, $root_len ), $POLL_MODIFIED ] if $poll->{stat}->{$file}->[9] != $stat->{$file}->[9];
                    }
                    else {
                        push @changes, [ $poll->{abs} ? $file : substr( $file, $root_len ), $POLL_CREATED ];
                    }

                    $poll->{stat}->{$file} = $stat->{$file};
                }

                # scan removed entries
                for my $file ( keys $poll->{stat}->%* ) {
                    if ( !exists $stat->{$file} ) {
                        delete $poll->{stat}->{$file};

                        push @changes, [ $poll->{abs} ? $file : substr( $file, $root_len ), $POLL_REMOVED ];
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
## |    3 | 22                   | Subroutines::ProhibitExcessComplexity - Subroutine "poll" with high complexity score (31)                      |
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
