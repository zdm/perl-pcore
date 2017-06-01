package Pcore::Core::Event::Listener::Pipe::stderr;

use Pcore -class, -ansi;
use Pcore::Util::Text qw[remove_ansi];
use Pcore::Util::Data qw[to_json];

with qw[Pcore::Core::Event::Listener::Pipe];

has header => ( is => 'ro', isa => Str, default => $BOLD . $GREEN . '[<: $date.strftime("%Y-%m-%d %H:%M:%S.%4N") :>]' . $BOLD . $YELLOW . '[<: $channel :>]' . $BOLD . $RED . '[<: $level :>]' . $RESET );

has _tmpl => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Template'], init_arg => undef );
has _is_ansi => ( is => 'ro', isa => Bool, init_arg => undef );

has _init => ( is => 'ro', isa => Bool, init_arg => undef );

sub sendlog ( $self, $ev, $event ) {
    return if $ENV->{PCORE_LOG_STDERR_DISABLED};

    # init
    if ( !$self->{_init} ) {
        $self->{_init} = 1;

        # init template
        $self->{_tmpl} = P->tmpl;

        my $template = qq[$self->{header} <: \$title | raw :>
: if \$data {
<: \$data | raw :>
: }];

        $self->{_tmpl}->cache_string_tmpl( message => \$template );

        # check ansi support
        $self->{_is_ansi} //= -t $STDERR_UTF8 ? 1 : 0;    ## no critic qw[InputOutput::ProhibitInteractiveTest]
    }

    # sendlog
    {
        # prepare date object
        local $event->{date} = P->date->from_epoch( $event->{timestamp} );

        # prepare data
        local $event->{data} = $event->{data};

        # serialize reference
        $event->{data} = to_json( $event->{data}, readable => 1 )->$* if ref $event->{data};

        # indent
        $event->{data} =~ s/^/    /smg if defined $event->{data};

        my $message = $self->{_tmpl}->render( 'message', $event );

        remove_ansi $message->$* if !$self->{_is_ansi};

        print {$STDERR_UTF8} $message->$*;
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 26                   | ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 40, 43               | Variables::ProhibitLocalVars - Variable declared as "local"                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 9                    | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Event::Listener::Pipe::stderr

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
