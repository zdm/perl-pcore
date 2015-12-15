package Pcore::Core::Exception::Object;

use Pcore -class, -const, -export => { CONST => [ '$ERROR', '$WARN' ] };
use Devel::StackTrace qw[];
use Scalar::Util qw[blessed];    ## no critic qw[Modules::ProhibitEvilModules]

use overload                     #
  q[""] => sub {

    # string overloading can happens only from perl internals calls, such as eval in "use" or "require", or not handled "die", so we don't need full trace here
    return $_[0]->to_string( short_trace => 1 ) . $LF;
  },
  q[0+] => sub {
    return $_[0]->exit_code;
  },
  bool => sub {
    return 1;
  },
  fallback => undef;

const our $ERROR => 1;
const our $WARN  => 2;

has msg       => ( is => 'ro', isa => Str, default => q[] );
has exit_code => ( is => 'rw', isa => Int, builder => 1 );
has level => ( is => 'ro', isa => Enum [ $ERROR, $WARN ], required => 1 );
has ns          => ( is => 'lazy', isa => Str );
has propagated  => ( is => 'ro',   isa => Bool, default => 0 );
has skip_frames => ( is => 'ro',   isa => Int, default => 0 );
has trace       => ( is => 'rwp',  isa => Bool, default => 1 );
has from_hook   => ( is => 'ro',   isa => Bool, default => 0 );    # check message for "\n", skip any message modifications if "\n" exists, do not add trace

# automatically defined on BUILD call
has _trace => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has _caller_frame => ( is => 'lazy', isa => InstanceOf ['Devel::StackTrace::Frame'], clearer => 1, init_arg => undef );

has _to_string      => ( is => 'lazy', isa => HashRef, init_arg => undef );
has _logged         => ( is => 'rw',   isa => Bool,    default  => 0, init_arg => undef );
has _stop_propagate => ( is => 'rw',   isa => Bool,    default  => 0, init_arg => undef );

around new => sub ( $orig, $self, $msg, %args ) {
    if ( blessed $msg ) {
        my $ref = ref $msg;

        if ( $ref eq __PACKAGE__ ) {    # already catched
            return $msg;
        }
        elsif ( $ref eq 'Error::TypeTiny::Assertion' ) {    # catch Moose exceptions
            $msg = $msg->message;

            # skip frames: Error::TypeTiny::throw, Type::Tiny::_failed_check, eval {...}
            $args{skip_frames} += 3;
        }
        elsif ( $ref =~ /\AMoose::Exception/sm ) {          # catch Moose exceptions
            $msg = $msg->message;
        }
        else {                                              # foreign exception object returned as-is
            return;
        }
    }

    # always skip current method call and eval below
    $args{skip_frames} += 2;

    # handle errors during exception object creation
    local $@;

    my $e = eval {

        # stringify $msg
        $self->$orig( { %args, msg => "$msg" } );    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]
    };

    return $e;
};

no Pcore;

# CLASS METHODS
sub PROPAGATE {
    my $self = shift;
    my $file = shift;
    my $line = shift;

    return $self;
}

# OBJECT METHODS
sub BUILD {
    my $self = shift;

    $self->_trace;

    $self->_caller_frame;

    return;
}

sub _build_exit_code ($self) {

    # return $! if $!;              # errno
    # return $? >> 8 if $? >> 8;    # child exit status
    return 255;    # last resort
}

sub _build__trace ($self) {
    my $trace = Devel::StackTrace->new(
        unsafe_ref_capture => 0,
        no_args            => 1,
        max_arg_length     => 32,
        indent             => 0,
        skip_frames        => $self->skip_frames + 4,    # skip BUILD and _build__trace methods
    );

    my @frames = $trace->frames;

    return \@frames;
}

sub _build__caller_frame ($self) {
    return shift $self->_trace->@*;
}

sub _build_ns ($self) {
    return $self->caller_package;
}

sub caller_package ($self) {
    return $self->_caller_frame->package;
}

sub is_propagated ( $self, @propagate ) {
    if ( !$self->propagated ) {
        return;
    }
    else {
        if (@propagate) {
            return uc( $self->msg ) ~~ @propagate ? 1 : 0;
        }
        else {
            return 1;
        }
    }
}

sub _build__to_string ($self) {
    my $res = {
        msg    => $self->msg,
        caller => ', caught at ' . $self->_caller_frame->filename . ' line ' . $self->_caller_frame->line . q[.],
        trace  => $self->_trace->@* ? join( qq[\n], map { q[ ] x 4 . $_->as_string } $self->_trace->@* ) : q[],
    };

    {
        local $/ = q[];    # remove all trailing newlines with chomp

        my $ended_with_newline = chomp $res->{msg};

        # disable trace if exception was catched from die / warn call and message is ended with "\n"
        $self->_set_trace(0) if $ended_with_newline && $self->from_hook;
    }

    return $res;
}

sub to_string {
    my $self = shift;
    my %args = (
        trace       => undef,
        short_trace => 0,
        @_,
    );

    my $as_string = $self->_to_string;

    $args{trace} //= $self->trace;

    my $str = $as_string->{msg};
    if ( $args{trace} || $args{short_trace} ) {
        $str .= $as_string->{caller} if $self->from_hook;    # perl automatically add this info if exception came not from "die" call

        $str .= qq[\n] . $as_string->{trace} if $as_string->{trace} && !$args{short_trace};    # if has collected call stack
    }

    return $str;
}

sub send_log {
    my $self = shift;
    my %args = (
        force  => 0,                                                                           # force logging if already logged
        level  => $self->level,
        ns     => $self->ns,
        header => undef,
        tags   => {},
        @_,
    );

    return 0 if $self->_logged && !$args{force};                                               # prevent doble logging same exception

    $self->_logged(1);

    $args{tags} = {
        package    => $self->caller_package,
        filename   => $self->_caller_frame->filename,
        line       => $self->_caller_frame->line,
        subroutine => $self->_caller_frame->subroutine,
        $args{tags}->%*,
    };

    return Pcore::Core::Log::send_log( [ $self->to_string ], level => $args{level}, ns => $args{ns}, header => $args{header}, tags => $args{tags} );
}

sub propagate ($self) {
    if ( $self->level eq $ERROR ) {
        return die $self;
    }
    else {
        return warn $self;
    }
}

sub stop_propagate ($self) {
    return $self->_stop_propagate(1);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 66                   │ Variables::RequireInitializationForLocalVars - "local" variable not initialized                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 207                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 3                    │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Exception::Object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
