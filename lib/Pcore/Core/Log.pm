package Pcore::Core::Log;

use Pcore -const,
  -export => {
    ALL     => [qw[has_logs error info debug set_log]],
    CORE    => [qw[set_log]],
    DEFAULT => [qw[has_logs error info debug]],
  };

const our $LEVELS => {
    FATAL => 1,
    ERROR => 2,
    WARN  => 3,
    INFO  => 4,
    DEBUG => 5
};

our $DISABLED_CHANNELS = {};
our $REGISTRY          = {};
our $PIPES             = {};

# add default log channels
# register CORE#DAEMONIZE event - disable console log
sub CORE_INIT {

    # set default log pipes
    for my $pipe ( $PROC->pcore->cfg->{log} ? $PROC->pcore->cfg->{log}->@* : (), $PROC->{CFG}->{log} ? $PROC->{CFG}->{log}->@* : () ) {
        __PACKAGE__->set_log( $pipe->%* );
    }

    P->EV->register( 'CORE#DAEMONIZE' => \&core_daemonize_event, disposable => 1 );

    return;
}

sub core_daemonize_event {
    my $ev = shift;

    disable_channel('Console');

    return;
}

sub set_log {
    my $self = shift;
    my %args = (
        level   => q[*],
        ns      => q[*],
        channel => undef,
        stream  => undef,
        header  => undef,
        @_,
    );

    die 'Channel must be specified' unless $args{channel};

    return if !is_channel_enabled( $args{channel} );    # skip disabled channels

    unless ( ref $args{ns} eq 'Regexp' ) {
        if ( $args{ns} eq q[*] ) {
            $args{ns} = qr/\A.+\z/smi;
        }
        else {
            $args{ns} = qr/\A\Q$args{ns}\E\z/smi;
        }
    }

    delete $args{stream} unless defined $args{stream};

    delete $args{header} unless defined $args{header};

    my $temp = defined wantarray ? 1 : 0;
    my $pipe = P->class->load( $args{channel}, ns => 'Pcore::LogChannel', does => 'Pcore::Core::Log::Channel' )->new( \%args );
    my $pipe_id = $pipe->id;

    unless ( $PIPES->{$pipe_id} ) {
        $PIPES->{$pipe_id} = $pipe;
        P->scalar->weaken( $PIPES->{$pipe_id} );    # pipe ref always weaken
    }
    else {
        $pipe = $PIPES->{$pipe_id};
    }

    my $levels_to_add = {};
    if ( ref $args{level} eq 'ARRAY' ) {
        foreach my $level ( $args{level}->@* ) {
            _parse_level( uc $level, $levels_to_add );
        }
    }
    else {
        _parse_level( uc $args{level}, $levels_to_add );
    }

    foreach my $level ( keys $levels_to_add->%* ) {
        $REGISTRY->{$level}->{ $args{ns} }->{ns} = $args{ns};    # create ns entry

        if ( $REGISTRY->{$level}->{ $args{ns} }->{$pipe_id} ) {
            $REGISTRY->{$level}->{ $args{ns} }->{$pipe_id} = $pipe if !$temp;
        }
        else {
            $REGISTRY->{$level}->{ $args{ns} }->{$pipe_id} = $pipe;
            P->scalar->weaken( $REGISTRY->{$level}->{ $args{ns} }->{$pipe_id} ) if $temp;
        }
    }

    if ($temp) {
        return $pipe;
    }
    else {
        return;
    }
}

sub _parse_level {
    my $level         = shift;
    my $levels_to_add = shift;

    if ( $level =~ /\A[!](.*)\z/sm ) {
        die qq[Incorrect log level "$1"] if !exists $LEVELS->{$1};
        delete $levels_to_add->{$1};
    }
    elsif ( $level =~ /\A<=(.*)\z/sm ) {
        die qq[Incorrect log level "$1"] if !exists $LEVELS->{$1};
        foreach my $l ( keys $LEVELS->%* ) {
            $levels_to_add->{$l} = 1 if $LEVELS->{$l} <= $LEVELS->{$1};
        }
    }
    elsif ( $level =~ /\A>=(.*)\z/sm ) {
        die qq[Incorrect log level "$1"] if !exists $LEVELS->{$1};
        foreach my $l ( keys $LEVELS->%* ) {
            $levels_to_add->{$l} = 1 if $LEVELS->{$l} >= $LEVELS->{$1};
        }
    }
    elsif ( $level eq q[*] ) {
        foreach my $l ( keys $LEVELS->%* ) {
            $levels_to_add->{$l} = 1;
        }
    }
    else {
        die qq[Incorrect log level "$level"] if !exists $LEVELS->{$level};
        $levels_to_add->{$level} = 1;
    }

    return;
}

sub _has_logs {
    my %args = (
        level => undef,
        ns    => undef,
        @_,
    );

    return [] unless $REGISTRY->{ $args{level} };

    my $pipes_ids = {};
    for my $ns ( grep { defined $REGISTRY->{ $args{level} }->{$_}->{ns} && $args{ns} =~ /$REGISTRY->{$args{level}}->{$_}->{ns}/sm } keys $REGISTRY->{ $args{level} }->%* ) {
        my @ns_pipes = grep { $_ ne 'ns' && defined $REGISTRY->{ $args{level} }->{$ns}->{$_} } keys $REGISTRY->{ $args{level} }->{$ns}->%*;
        unless ( scalar @ns_pipes ) {    # cleanup namespaces without defined pipes
            delete $REGISTRY->{ $args{level} }->{$ns};
            next;
        }
        else {
            for (@ns_pipes) {
                $pipes_ids->{$_} = 1;
            }
        }
    }

    return [ map { $PIPES->{$_} } keys $pipes_ids->%* ];
}

sub disable_channel {
    my $channel = lc shift;

    $DISABLED_CHANNELS->{$channel} = 1;
    for my $level ( keys $REGISTRY->%* ) {
        for my $ns ( keys $REGISTRY->{$level}->%* ) {
            for my $pipe_id ( grep { $_ ne 'ns' } keys $REGISTRY->{$level}->{$ns}->%* ) {

                # delete undefined pipes, or pipes which belongs to disabled channel
                delete $REGISTRY->{$level}->{$ns}->{$pipe_id} if !defined $REGISTRY->{$level}->{$ns}->{$pipe_id} || $REGISTRY->{$level}->{$ns}->{$pipe_id}->channel eq $channel;
            }
            delete $REGISTRY->{$level}->{$ns} if scalar keys $REGISTRY->{$level}->{$ns}->%* == 1;    # delete namespaces with no pipes
        }
        delete $REGISTRY->{$level} unless scalar keys $REGISTRY->{$level}->%*;                       # delete levels with no namespaces
    }

    return;
}

# LOG METHODS
sub has_logs {
    my %args = (
        level => undef,
        ns    => caller,
        @_,
    );
    my $pipes = _has_logs(%args);
    return scalar $pipes->@*;
}

sub error {
    my @caller = caller;
    return send_log( \@_, level => 'ERROR', ns => $caller[0], header => undef, tags => { package => $caller[0], filename => $caller[1], line => $caller[2], subroutine => $caller[3] } );
}

sub info {
    my @caller = caller;
    return send_log( \@_, level => 'INFO', ns => $caller[0], header => undef, tags => { package => $caller[0], filename => $caller[1], line => $caller[2], subroutine => $caller[3] } );
}

sub debug {
    my @caller = caller;
    return send_log( \@_, level => 'DEBUG', ns => $caller[0], header => undef, tags => { package => $caller[0], filename => $caller[1], line => $caller[2], subroutine => $caller[3] } );
}

# INTERNALS
sub is_channel_enabled {
    my $channel = shift;

    return !$DISABLED_CHANNELS->{$channel};
}

sub send_log {
    my $data_ref = shift;
    my %args     = (
        level  => undef,
        ns     => undef,
        header => undef,
        tags   => {},
        @_,
    );

    return unless $data_ref->@*;

    my $pipes = _has_logs(%args);    # cleanup REGISTRY and get active pipes

    return unless scalar $pipes->@*;

    $args{tags}->{filename} =~ s[\\][/]smg if $MSWIN && $args{tags}->{filename};

    # prepare output data
    my $data;
    for ( $data_ref->@* ) {
        push $data->{color}->@*, $_ . q[];    # stringify
    }

    my $time = P->date->now_utc;

    my $resolved_headers = {};

    my $pipe_ids = {};

    for my $pipe ( sort { $a->priority <=> $b->priority } $pipes->@* ) {
        my $pipe_id = $pipe->id( header => $args{header} );

        unless ( $pipe_ids->{$pipe_id} ) {
            $pipe_ids->{$pipe_id} = 1;

            my $prev_error = $@;

            eval {    ## no critic qw[ErrorHandling::RequireCheckingReturnValueOfEval]
                local $SIG{__DIE__} = undef;

                local $SIG{__WARN__} = undef;

                $pipe->send_log( %args, header => _resolve_header( $args{header} // $pipe->header, $resolved_headers, %args, time => $time ), data => _resolve_data_colors( $pipe->color, $data ) );

                1;
            };

            $@ = $prev_error;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
        }
    }

    return 1;
}

sub _resolve_header {
    my $header           = shift;
    my $resolved_headers = shift;
    my %args             = @_;

    return q[] unless $header;

    unless ( exists $resolved_headers->{$header} ) {
        my $ID = P->sys->pid;

        my $resolved_header = $header;

        $resolved_header =~ s/%ID/$ID/smg;

        $resolved_header =~ s/%NS/$args{ns}/smg;

        $resolved_header =~ s/%LEVEL/$args{level}/smg;

        $resolved_header = $args{time}->strftime($resolved_header);

        $resolved_headers->{$header} = $resolved_header;
    }

    return $resolved_headers->{$header};
}

sub _resolve_data_colors {
    my $color = shift;
    my $data  = shift;

    if ( !$color ) {
        unless ( exists $data->{no_color} ) {
            $data->{no_color} = [];
            for my $str ( $data->{color}->@* ) {
                push $data->{no_color}->@*, $str;
                P->text->remove_ansi_color( $data->{no_color}->[-1] );
            }
        }
        return $data->{no_color};
    }
    else {
        return $data->{color};
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 28, 94, 124, 130,    │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 135, 157, 158, 170,  │                                                                                                                │
## │      │ 177, 178, 179, 184,  │                                                                                                                │
## │      │ 186                  │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 44                   │ Subroutines::ProhibitExcessComplexity - Subroutine "set_log" with high complexity score (21)                   │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NOTES

=head1 SET LOG PIPE

    set_pipe(channel => $channel[, ns => $namespace, level => $level, stream => $stream, format => $format]);
    __PACKAGE__->set_pipe(...);
    $self->set_pipe(...);

=head2 LEVEL

=over

=item * * - all possible levels, this is default behaviour;

=item * LEVEL

=item * >=LEVEL

=item * <=LEVEL

=item * !LEVEL

=back

=cut
