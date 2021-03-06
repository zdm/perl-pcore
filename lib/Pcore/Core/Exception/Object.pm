package Pcore::Core::Exception::Object;

use Pcore -class;
use Pcore::Util::Scalar qw[blessed];
use Time::HiRes qw[];

use overload    #
  q[""] => sub {

    # string overloading can happens only from perl internals calls, such as eval in "use" or "require" (or other compilation errors), or not handled "die", so we don't need full trace here
    return "$_[0]->{msg}\n";
  },
  q[0+] => sub {
    return $_[0]->exit_code;
  },
  bool => sub {
    return 1;
  },
  fallback => undef;

has msg        => ( required => 1 );
has level      => ( required => 1 );    # Enum [qw[ERROR WARN]]
has call_stack => ( required => 1 );
has timestamp  => ( required => 1 );

has exit_code  => ( is => 'lazy' );
has with_trace => 1;

has longmess  => ( is => 'lazy', init_arg => undef );
has to_string => ( is => 'lazy', init_arg => undef );
has is_logged => ( init_arg => undef );

around new => sub ( $orig, $self, $msg, %args ) {
    $args{skip_frames} //= 0;

    if ( my $blessed = blessed $msg ) {

        # already cought
        if ( $blessed eq __PACKAGE__ ) {
            return $msg;
        }

        # catch TypeTiny exceptions
        elsif ( $blessed eq 'Error::TypeTiny::Assertion' ) {
            $msg = $msg->message;

            # skip frames: Error::TypeTiny::throw
            $args{skip_frames} += 1;
        }

        # catch Moose exceptions
        elsif ( $blessed =~ /\AMoose::Exception/sm ) {
            $msg = $msg->message;
        }

        # other foreign exception objects are returned as-is
        # else {
        #     return;
        # }
    }

    # cut trailing "\n" from $msg
    {
        local $/ = $EMPTY;

        chomp $msg;
    };

    my $x = $args{skip_frames} + 2;

    my @frames;

    while ( my @frame = caller $x++ ) {
        push @frames, "$frame[3] at $frame[1] line $frame[2]";
    }

    $args{call_stack} = \join "\n", @frames if @frames;

    $args{timestamp} = Time::HiRes::time();

    # stringify $msg
    $args{msg} = "$msg";

    return bless \%args, $self;
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
    if ( $self->{call_stack} ) {
        return "$self->{msg}\n" . ( $self->{call_stack}->$* =~ s/^/    /smgr );
    }
    else {
        return $self->{msg};
    }
}

sub _build_to_string ($self) {
    return $self->{with_trace} ? $self->longmess : $self->{msg};
}

sub sendlog ( $self, $level = undef ) {
    return if $self->{is_logged};    # prevent logging the same exception twice

    $level //= $self->{level};

    $self->{is_logged} = 1;

    P->sendlog( "EXCEPTION.$level", $self->{msg}, $self->{with_trace} ? $self->{call_stack}->$* : undef );

    return;
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
