package Pcore::Util::Path::Poll;

use Pcore -role, -const, -export;
use Pcore::Util::Scalar qw[is_plain_coderef];
use Time::HiRes qw[];
use Coro::Signal qw[];

const our $DEFAULT_POLL_INTERVAL => 3;

const our $POLL_CREATED  => 1;
const our $POLL_MODIFIED => 2;
const our $POLL_REMOVED  => 3;

const our $POLL_TYPE_TREE => 1;
const our $POLL_TYPE_FILE => 2;

our $EXPORT = { POLL => [qw[$POLL_CREATED $POLL_MODIFIED $POLL_REMOVED]] };

sub poll_tree ( $self, @ ) {
    state $POLL_INTERVAL = $DEFAULT_POLL_INTERVAL;
    state $POLL;
    state $SIGNAL = Coro::Signal->new;
    state $thread;

    my $cb = is_plain_coderef $_[-1] ? pop : ();

    my $root = $self->to_abs;

    my $poll = $POLL->{$root} = {
        poll_type    => $POLL_TYPE_TREE,
        read_dir     => { @_[ 1 .. $#_ ] },
        root         => $root,
        last_checked => 0,
        cb           => $cb,
    };

    $poll->{interval} = delete( $poll->{read_dir}->{interval} ) // $DEFAULT_POLL_INTERVAL;

    $POLL_INTERVAL = $poll->{interval} if $poll->{interval} < $POLL_INTERVAL;

    # initial scan
    if ( -d $poll->{root} && ( my $paths = $poll->{root}->read_dir( $poll->{read_dir}->%* ) ) ) {
        for my $path ( $paths->@* ) {
            my $path_abs_encoded = $path->{is_abs} ? $path->encoded : $poll->{root}->encoded . '/' . $path->encoded;

            $poll->{stat}->{$path_abs_encoded} = [ $path, [ Time::HiRes::stat($path_abs_encoded) ] ];
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
                if ( -d $poll->{root} && ( my $paths = $poll->{root}->read_dir( $poll->{read_dir}->%* ) ) ) {
                    for my $path ( $paths->@* ) {
                        my $path_abs_encoded = $path->{is_abs} ? $path->encoded : $poll->{root}->encoded . '/' . $path->encoded;

                        $stat->{$path_abs_encoded} = [ $path, [ Time::HiRes::stat($path_abs_encoded) ] ];
                    }
                }

                my @changes;

                # scan created / modified paths
                for my $path ( keys $stat->%* ) {

                    # path is already exists
                    if ( exists $poll->{stat}->{$path} ) {

                        # last modify time was changed
                        if ( $poll->{stat}->{$path}->[1]->[9] != $stat->{$path}->[1]->[9] ) {
                            push @changes, [ $stat->{$path}->[0], $POLL_MODIFIED ];
                        }
                    }

                    # new path was created
                    else {
                        push @changes, [ $stat->{$path}->[0], $POLL_CREATED ];
                    }

                    $poll->{stat}->{$path} = $stat->{$path};
                }

                # scan removed paths
                for my $path ( keys $poll->{stat}->%* ) {

                    # path was removed
                    if ( !exists $stat->{$path} ) {
                        push @changes, [ $poll->{stat}->{$path}->[0], $POLL_REMOVED ];

                        delete $poll->{stat}->{$path};
                    }
                }

                # call callback if has changes
                $poll->{cb}->( $poll->{root}, \@changes ) if @changes;
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
## |    3 | 19                   | Subroutines::ProhibitExcessComplexity - Subroutine "poll_tree" with high complexity score (24)                 |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path::Poll

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
