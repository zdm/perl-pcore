package Pcore::Core::Exception::Object;

use Pcore -class, -const, -export => { CONST => [qw[$FATAL $ERROR $WARN]] };
use Devel::StackTrace qw[];
use Scalar::Util qw[blessed];    ## no critic qw[Modules::ProhibitEvilModules]

use overload                     #
  q[""] => sub {

    # string overloading can happens only from perl internals calls, such as eval in "use" or "require", or not handled "die", so we don't need full trace here
    return $_[0]->shortmess . $LF;
  },
  q[0+] => sub {
    return $_[0]->exit_code;
  },
  bool => sub {
    return 1;
  },
  fallback => undef;

const our $FATAL => 'FATAL';
const our $ERROR => 'ERROR';
const our $WARN  => 'WARN';

has msg => ( is => 'ro', isa => Str, required => 1 );
has exit_code => ( is => 'lazy', isa => Int );
has level => ( is => 'ro', isa => Enum [ $ERROR, $WARN ], required => 1 );
has trace      => ( is => 'ro', isa => Bool,     default  => 1 );
has call_stack => ( is => 'ro', isa => ArrayRef, required => 1 );
has caller_frame => ( is => 'ro', isa => InstanceOf ['Devel::StackTrace::Frame'], required => 1 );

has propagated => ( is => 'ro', isa => Bool, default => 0 );
has ns => ( is => 'lazy', isa => Str );

has shortmess => ( is => 'lazy', isa => Str, init_arg => undef );
has longmess  => ( is => 'lazy', isa => Str, init_arg => undef );
has to_string => ( is => 'lazy', isa => Str, init_arg => undef );

has _logged         => ( is => 'rw', isa => Bool, default => 0, init_arg => undef );
has _stop_propagate => ( is => 'rw', isa => Bool, default => 0, init_arg => undef );

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

    # cut trailing "\n" from $msg
    my $ended_with_newline = do {
        local $/ = q[];                                     # remove all trailing newlines with chomp

        chomp $msg;
    };

    # disable trace if exception was catched from die / warn call and message is ended with "\n"
    $args{trace} = 0 if $ended_with_newline;

    # handle errors during exception object creation
    local $@;

    my $e = eval {

        # build stack trace
        my $trace = Devel::StackTrace->new(
            unsafe_ref_capture => 0,
            no_args            => 0,
            max_arg_length     => 32,
            indent             => 0,
            skip_frames        => $args{skip_frames} + 4,    # skip useless frames
        );

        $args{call_stack} = [ $trace->frames ];

        $args{caller_frame} = shift $args{call_stack}->@*;

        # stringify $msg
        $self->$orig( { %args, msg => "$msg" } );            ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]
    };

    return $e;
};

no Pcore;

# CLASS METHODS
sub PROPAGATE ( $self, $file, $line ) {
    return $self;
}

sub _build_exit_code ($self) {

    # return $! if $!;              # errno
    # return $? >> 8 if $? >> 8;    # child exit status
    return 255;    # last resort
}

sub _build_ns ($self) {
    return $self->caller_frame->package;
}

sub _build_shortmess ($self) {
    return $self->msg . ', at ' . $self->caller_frame->filename . ' line ' . $self->caller_frame->line;
}

sub _build_longmess ($self) {
    if ( $self->call_stack->@* ) {
        return $self->shortmess . $LF . join $LF, map { q[ ] x 4 . $_->as_string } $self->call_stack->@*;
    }
    else {
        return $self->shortmess;
    }
}

sub _build_to_string ($self) {
    return $self->trace ? $self->longmess : $self->msg;
}

sub send_log ( $self, @ ) {
    my %args = (
        force  => 0,              # force logging if already logged
        level  => $self->level,
        ns     => $self->ns,
        header => undef,
        tags   => {},
        splice @_, 1,
    );

    return 0 if $self->_logged && !$args{force};    # prevent doble logging same exception

    $self->_logged(1);

    $args{tags} = {
        package    => $self->caller_frame->package,
        filename   => $self->caller_frame->filename,
        line       => $self->caller_frame->line,
        subroutine => $self->caller_frame->subroutine,
        $args{tags}->%*,
    };

    return Pcore::Core::Log::send_log( [ $self->to_string ], level => $args{level}, ns => $args{ns}, header => $args{header}, tags => $args{tags} );
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
## │    3 │ 74                   │ Variables::RequireInitializationForLocalVars - "local" variable not initialized                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 152                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
