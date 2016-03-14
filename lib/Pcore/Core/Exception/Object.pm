package Pcore::Core::Exception::Object;

use Pcore -class;
use Devel::StackTrace qw[];
use Pcore::Util::Scalar qw[blessed];

use overload    #
  q[""] => sub {

    # string overloading can happens only from perl internals calls, such as eval in "use" or "require" (or other compilation errors), or not handled "die", so we don't need full trace here
    return $_[0]->msg . $LF;
  },
  q[0+] => sub {
    return $_[0]->exit_code;
  },
  bool => sub {
    return 1;
  },
  fallback => undef;

has msg => ( is => 'ro', isa => Str, required => 1 );
has exit_code => ( is => 'lazy', isa => Int );
has level => ( is => 'ro', isa => Enum [qw[ERROR WARN]], required => 1 );
has trace      => ( is => 'ro', isa => Bool,     default  => 1 );
has call_stack => ( is => 'ro', isa => ArrayRef, required => 1 );
has caller_frame => ( is => 'lazy', isa => InstanceOf ['Devel::StackTrace::Frame'], required => 1 );

has propagated => ( is => 'ro', isa => Bool, default => 0 );

has longmess  => ( is => 'lazy', isa => Str, init_arg => undef );
has to_string => ( is => 'lazy', isa => Str, init_arg => undef );

has logged          => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );
has _stop_propagate => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

around new => sub ( $orig, $self, $msg, %args ) {
    $args{skip_frames} //= 0;

    if ( blessed $msg ) {
        my $ref = ref $msg;

        if ( $ref eq __PACKAGE__ ) {    # already cought
            return $msg;
        }
        elsif ( $ref eq 'Error::TypeTiny::Assertion' ) {    # catch TypeTiny exceptions
            $msg = $msg->message;

            # skip frames: Error::TypeTiny::throw, Type::Tiny::_failed_check, eval {...}
            $args{skip_frames} += 3;
        }
        elsif ( $ref =~ /\AMoose::Exception/sm ) {          # catch Moose exceptions
            $msg = $msg->message;
        }
        else {                                              # other foreign exception objects are returned as-is
            return;
        }
    }

    # cut trailing "\n" from $msg
    {
        local $/ = q[];

        chomp $msg;
    };

    # collect stack trace
    $args{call_stack} = [
        Devel::StackTrace->new(
            unsafe_ref_capture => 0,
            no_args            => 1,
            max_arg_length     => 32,
            indent             => 0,
            skip_frames        => $args{skip_frames} + 3,    # skip useless frames: Devel::StackTrace::new, around new, new
        )->frames
    ];

    $args{caller_frame} = $args{call_stack}->[0];

    # stringify $msg
    return $self->$orig( { %args, msg => "$msg" } );         ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]
};

# CLASS METHODS
sub PROPAGATE ( $self, $file, $line ) {
    return $self;
}

sub _build_exit_code ($self) {

    # return $! if $!;              # errno
    # return $? >> 8 if $? >> 8;    # child exit status
    return 255;    # last resort
}

sub _build_longmess ($self) {
    return $self->msg . $LF . join $LF, map { q[ ] x 4 . $_->as_string } $self->call_stack->@*;
}

sub _build_to_string ($self) {
    return $self->trace ? $self->longmess : $self->msg;
}

sub sendlog ( $self, @ ) {
    my %args = (
        force      => 0,                                 # force logging if already logged
        channel    => $self->level,
        package    => $self->caller_frame->package,
        filename   => $self->caller_frame->filename,
        line       => $self->caller_frame->line,
        subroutine => $self->caller_frame->subroutine,
        splice @_, 1,
    );

    return 0 if $self->{logged} && !delete $args{force};    # prevent logging same exception twice

    $self->{logged} = 1;

    my $channel = lc delete $args{channel};

    P->log->sendlog( $channel, $self->to_string, %args );

    return;
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
    if ( $self->level eq 'ERROR' ) {
        CORE::die $self;

        return;
    }
    else {
        CORE::warn $self;

        return;
    }
}

sub stop_propagate ($self) {
    $self->{_stop_propagate} = 1;

    return 1;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Exception::Object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
