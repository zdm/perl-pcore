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
# + read_dir options
sub poll ( $self, @ ) {
    state $POLL_INTERVAL = $DEFAULT_POLL_INTERVAL;
    state $POLL;
    state $SIGNAL = Coro::Signal->new;
    state $thread;

    my $cb = is_plain_coderef $_[-1] ? pop : ();

    my $path = $self->to_abs;

    my $poll = $POLL->{$path} = {
        root         => 1,                        # monitor root path
        recursive    => 1,                        # scan subdirs if root is dir
        abs          => 0,                        # report absolute paths
        read_dir     => { @_[ 1 .. $#_ ] },
        path         => $path,
        interval     => $DEFAULT_POLL_INTERVAL,
        last_checked => 0,
        cb           => $cb,
    };

    $poll->{root}      = delete $poll->{read_dir}->{root}                                  if exists $poll->{read_dir}->{root};
    $poll->{abs}       = delete $poll->{read_dir}->{abs}                                   if exists $poll->{read_dir}->{abs};
    $poll->{recursive} = delete $poll->{read_dir}->{recursive}                             if exists $poll->{read_dir}->{recursive};
    $poll->{interval}  = delete( $poll->{read_dir}->{interval} ) // $DEFAULT_POLL_INTERVAL if exists $poll->{read_dir}->{interval};

    $POLL_INTERVAL = $poll->{interval} if $poll->{interval} < $POLL_INTERVAL;

    # initial scan
    if ( -e $path ) {

        # add root path
        $poll->{stat}->{$path} = [ Time::HiRes::stat($path) ] if $poll->{root};

        # add child paths
        if ( $poll->{recursive} && -d _ && ( my $files = $path->read_dir( $poll->{read_dir}->%*, abs => 1 ) ) ) {
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
                next if $poll->{last_checked} + $poll->{interval} > time;

                $poll->{last_checked} = time;

                my $stat;

                # scan
                if ( -e $poll->{path} ) {

                    # add root path
                    $stat->{ $poll->{path} } = [ Time::HiRes::stat $poll->{path} ] if $poll->{root};

                    # add child paths
                    if ( $poll->{recursive} && -d _ && ( my $paths = $poll->{path}->read_dir( $poll->{read_dir}->%*, abs => 1 ) ) ) {
                        for my $path ( $paths->@* ) {
                            $stat->{$path} = [ Time::HiRes::stat($path) ];
                        }
                    }
                }

                my @changes;

                my $root_len = $poll->{abs} ? undef : 1 + length $poll->{path};

                # scan created / modified paths
                for my $path ( keys $stat->%* ) {

                    # path is already exists
                    if ( exists $poll->{stat}->{$path} ) {

                        # last modify time was changed
                        push @changes, [ $poll->{abs} ? $path : substr( $path, $root_len ), $POLL_MODIFIED ] if $poll->{stat}->{$path}->[9] != $stat->{$path}->[9];
                    }

                    # new path was created
                    else {
                        push @changes, [ $poll->{abs} ? $path : substr( $path, $root_len ), $POLL_CREATED ];
                    }

                    $poll->{stat}->{$path} = $stat->{$path};
                }

                # scan removed paths
                for my $path ( keys $poll->{stat}->%* ) {

                    # path was removed
                    if ( !exists $stat->{$path} ) {
                        delete $poll->{stat}->{$path};

                        push @changes, [ $poll->{abs} ? $path : substr( $path, $root_len ), $POLL_REMOVED ];
                    }
                }

                # call callback if has changes
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
## |    3 | 20                   | Subroutines::ProhibitExcessComplexity - Subroutine "poll" with high complexity score (36)                      |
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
